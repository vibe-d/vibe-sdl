vibe.d SDLang serialization
===========================

This package provides generic `vibe.data.seriailzation` based serialization
support for the [SDLang](https://sdlang.org/) data format. It uses 
[sdlang-d](https://code.dlang.org/packages/sdlang-d) to parse and generate
the SDLang format.

Example:

	import vibe.data.sdl : serializeSDL;
	import sdlang.ast : Tag;
	import std.stdio : writeln;

	struct Ticket {
		int id;
		string title;
		string[] tags;
	}

	void main()
	{
		Ticket[] tickets = [
			Ticket(0, "foo", ["defect", "critical"]),
			Ticket(1, "bar", ["enhancement"])
		];

		Tag sdl = serializeSDL(tickets);
		writeln(sdl.toSDLDocument());
	}
