/** SDLang data format serialization support for vibe.data.serialization.
*/
module vibe.data.sdl;

import vibe.data.serialization;
import sdlang;
import std.traits : Unqual, ValueType, isNumeric, isBoolean, isArray, isAssociativeArray;
import std.datetime : Date, DateTime, SysTime, TimeOfDay, UTC;
import core.time : Duration, days, hours, seconds;


///
unittest {
	static struct S {
		bool b;
		int i;
		float f;
		double d;
		string str;
		ubyte[] data;
		SysTime sysTime;
		DateTimeFrac dateTime;
		Date date;
		Duration dur;
	}

	S s = {
		b : true,
		i: 12,
		f: 0.5f,
		d: 0.5,
		str: "foo",
		data: [1, 2, 3],
		sysTime: SysTime(DateTime(Date(2016, 12, 10), TimeOfDay(9, 30, 23)), UTC()),
		dateTime: DateTimeFrac(DateTime(Date(2016, 12, 10), TimeOfDay(9, 30, 23))),
		date: Date(2016, 12, 10),
		dur: 2.days + 2.hours + 2.seconds
	};

	auto res = serializeSDLang(s);
	assert(res.toSDLDocument() == "b true\ni 12\nf 0.5F\nd 0.5D\nstr \"foo\"\ndata [AQID]\n"
		~ "sysTime 2016/12/10 09:30:23-UTC\ndateTime 2016/12/10 09:30:23\ndate 2016/12/10\n"
		~ "dur 2d:02:00:02\n", [res.toSDLDocument()].to!string);

	auto t = deserializeSDLang!S(res);
	assert(s == t);
}


///
unittest {
	static struct T {
		/*@sdlAttribute*/ int att1;
		/*@sdlAttribute*/ string att2;
		/*@sdlValue*/ string content1;
	}

	static struct S {
		string[string] dict;
		T[] arr;
		//@sdlSingle T[] arr2;
		int[] iarr;
	}

	S s = {
		dict : ["a": "foo", "b": "bar"],
		arr : [T(1, "a", "x"), T(2, "b", "y")],
	//	arr2 : [T(1, "a", "x"), T(2, "b", "y")],
		iarr : [1, 2, 3]
	};

	auto res = serializeSDLang(s);
	assert(res.toSDLDocument() ==
`dict {
	"b" "bar"
	"a" "foo"
}
arr {
	entry {
		att1 1
		att2 "a"
		content1 "x"
	}
	entry {
		att1 2
		att2 "b"
		content1 "y"
	}
}
iarr 1 2 3
`, res.toSDLDocument());

	S t = deserialize!(SDLangSerializer, S)(res);
	assert(s == t);
}

Tag serializeSDLang(T)(T value)
{
	return serialize!SDLangSerializer(value, new Tag(null, null));
}

T deserializeSDLang(T)(Tag sdl)
{
	return deserialize!(SDLangSerializer, T)(sdl);
}


///
struct SDLangSerializer {
	enum isSDLBasicType(T) =
		isNumeric!T ||
		isBoolean!T ||
		is(T == string) ||
		is(T == ubyte[]) ||
		is(T == SysTime) ||
		is(T == DateTime) ||
		is(T == DateTimeFrac) ||
		is(T == Date) ||
		is(T == Duration) ||
		is(T == typeof(null)) ||
		isSDLSerializable!T;

	enum isSupportedValueType(T) = isSDLBasicType!T || is(T == Tag);

	private enum Loc { subNodes, attribute, values }

	private static struct StackEntry {
		Tag tag;
		Attribute attribute;
		Loc loc;
		size_t valIdx;
		bool hasIdentKeys, isArrayEntry;
	}

	private {
		StackEntry[] m_stack;
	}

	this(Tag data) { pushTag(data); }

	@disable this(this);

	//
	// serialization
	//
	Tag getSerializedResult() { return m_stack[0].tag; }

	void beginWriteDictionary(T)() if (isValueDictionary!T) { current.hasIdentKeys = false; }
	void endWriteDictionary(T)()  if (isValueDictionary!T) {}
	void beginWriteDictionary(T)() if (!isValueDictionary!T) { current.hasIdentKeys = !isAssociativeArray!T; }
	void endWriteDictionary(T)()  if (!isValueDictionary!T) {}
	void beginWriteDictionaryEntry(T)(string name) {
		if (current.hasIdentKeys) pushTag(name);
		else pushTag(null, Value(name));
		current.loc = isSDLBasicType!T ? Loc.values : Loc.subNodes;
	}
	void endWriteDictionaryEntry(T)(string name) { pop(); }


	void beginWriteArray(T)(size_t) if (isValueArray!T) { current.loc = Loc.values; }
	void endWriteArray(T)() if (isValueArray!T) {}
	void beginWriteArray(T)(size_t) if (!isValueArray!T) { current.loc = Loc.subNodes; }
	void endWriteArray(T)() if (!isValueArray!T) {}
	void beginWriteArrayEntry(T)(size_t)
	{
		if (current.loc == Loc.subNodes) {
			pushTag("entry");
			current.isArrayEntry = true;
		}
	}
	void endWriteArrayEntry(T)(size_t)
	{
		if (current.isArrayEntry) pop();
	}

	void writeValue(T)(in T value)
		if (!is(T == Tag))
	{
		static if (isSDLSerializable!T) writeValue(value.toSDL());
		else {
			Value val;
			static if (is(T == DateTime)) val = DateTimeFrac(value);
			else {
				Unqual!T uval;
				static if (is(typeof(uval = value))) uval = value;
				else uval = value.dup;
				val = uval;
			}
			final switch (current.loc) {
				case Loc.attribute: current.attribute.value = val; break;
				case Loc.values: current.tag.add(val); break;
				case Loc.subNodes: current.tag.add(new Tag(null, null, [val])); break;
			}
		}
	}

	void writeValue(T)(Tag value) if (is(T == Tag)) { currentTag = value; }
	void writeValue(T)(in Json Tag) if (is(T == Tag)) { currentTag = value.clone; }

	//
	// deserialization
	//
	void readDictionary(T)(scope void delegate(string) field_handler)
		if (isValueDictionary!T)
	{
		foreach (st; current.tag.tags) {
			pushTag(st);
			current.loc = Loc.values;
			current.valIdx = 1;
			field_handler(st.values[0].get!string);
			pop();
		}
	}

	void readDictionary(T)(scope void delegate(string) field_handler)
		if (!isValueDictionary!T)
	{
		foreach (st; current.tag.tags) {
			pushTag(st);
			current.loc = Loc.values;
			current.valIdx = 0;
			field_handler(st.name);
			pop();
		}
	}

	void readArray(T)(scope void delegate(size_t) size_callback, scope void delegate() entry_callback)
		if (isValueArray!T)
	{
		current.loc = Loc.values;
		current.valIdx = 0;
		size_callback(current.tag.values.length);
		while (current.valIdx < current.tag.values.length) {
			entry_callback();
			current.valIdx++;
		}
	}

	void readArray(T)(scope void delegate(size_t) size_callback, scope void delegate() entry_callback)
		if (!isValueArray!T)
	{
		size_callback(current.tag.tags.length);
		foreach (st; current.tag.tags) {
			pushTag(st);
			entry_callback();
			pop();
		}
	}

	T readValue(T)() { return getCurrentValue().get!T; }
	bool tryReadNull() { return !getCurrentValue.hasValue(); }

	private @property ref inout(StackEntry) current() inout { return m_stack[$-1]; }

	private void pushTag(string name) { pushTag(new Tag(current.tag, null, name)); }
	private void pushTag(string name, Value value) { pushTag(new Tag(current.tag, null, name, [value])); }
	private void pushTag(Tag tag)
	{
		StackEntry se;
		se.tag = tag;
		se.valIdx = tag.values.length;
		m_stack ~= se;
	}

	private void pushAttribute(string name)
	{
		StackEntry se;
		se.attribute = new Attribute(null, name, Value.init);
		se.tag = current.tag;
		se.loc = Loc.attribute;
		current.tag.add(se.attribute);
		m_stack ~= se;
	}

	private void pop()
	{
		m_stack.length--;
		m_stack.assumeSafeAppend();
	}


	private Value getCurrentValue()
	{
		final switch (current.loc) {
			case Loc.attribute: return current.attribute.value;
			case Loc.values: return current.tag.values[current.valIdx];
			case Loc.subNodes: return current.tag.values[0];
		}
	}

	private template isValueDictionary(T) {
		static if (isAssociativeArray!T)
			enum isValueDictionary = isSDLBasicType!(ValueType!T);
		else enum isValueDictionary = false;
	}

	private template isValueArray(T) {
		static if (isArray!T)
			enum isValueArray = isSDLBasicType!(typeof(T.init[0]));
		else enum isValueArray = false;
	}
}

enum isSDLSerializable(T) = is(typeof(T.init.toSDL()) == Tag) && is(typeof(T.fromSDL(new Tag())) == T);

struct sdlAttribute {}
struct sdlSingle {}
