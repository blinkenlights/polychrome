defmodule Octopus.Font.BlinkenLightsRegular do
  require Octopus.Font
  alias Octopus.Font
  import Font

  @characters %{
    0 => %{
      encoding: 0,
      name: "defaultchar",
      bitmap:
        defbitmap([
          "XXXXXX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XXXXXX"
        ])
    },
    ?\s => %{
      encoding: ?\s,
      bitmap:
        defbitmap([
          "   ",
          "   ",
          "   ",
          "   ",
          "   ",
          "   ",
          "   "
        ])
    },
    ?! => %{
      encoding: ?!,
      bitmap:
        defbitmap([
          "XX",
          "XX",
          "XX",
          "XX",
          "XX",
          "  ",
          "XX"
        ])
    },
    ?" => %{
      encoding: ?",
      bitmap:
        defbitmap([
          "XX XX",
          "XX XX",
          "     ",
          "     ",
          "     ",
          "     ",
          "     "
        ])
    },
    ?# => %{
      encoding: ?#,
      bitmap:
        defbitmap([
          " XX XX ",
          " XX XX ",
          "XXXXXXX",
          " XX XX ",
          "XXXXXXX",
          " XX XX ",
          " XX XX "
        ])
    },
    ?$ => %{
      encoding: ?$,
      bitmap:
        defbitmap([
          "   XX   ",
          "  XXXXXX",
          "XX XX   ",
          "  XXXX  ",
          "   XX XX",
          "XXXXXX  ",
          "   XX   "
        ])
    },
    ?% => %{
      encoding: ?%,
      bitmap:
        defbitmap([
          "XX  XX",
          "XX  XX",
          "   XX ",
          "  XX  ",
          " XX   ",
          "XX  XX",
          "XX  XX"
        ])
    },
    ?& => %{
      encoding: ?&,
      bitmap:
        defbitmap([
          " XXXX   ",
          "XX  XX  ",
          "XX  XX  ",
          " XXXX   ",
          "XX XX XX",
          "XX  XX  ",
          " XXX XX "
        ])
    },
    ?' => %{
      encoding: ?',
      bitmap:
        defbitmap([
          "XX",
          "XX",
          "  ",
          "  ",
          "  ",
          "  ",
          "  "
        ])
    },
    ?( => %{
      encoding: ?(,
      bitmap:
        defbitmap([
          "  XX",
          " XX ",
          "XX  ",
          "XX  ",
          "XX  ",
          " XX ",
          "  XX"
        ])
    },
    ?) => %{
      encoding: ?),
      bitmap:
        defbitmap([
          "XX  ",
          " XX ",
          "  XX",
          "  XX",
          "  XX",
          " XX ",
          "XX  "
        ])
    },
    ?* => %{
      encoding: ?*,
      bitmap:
        defbitmap([
          "       ",
          "XX X XX",
          " XXXXX ",
          "XXXXXXX",
          " XXXXX ",
          "XX X XX",
          "       "
        ])
    },
    ?+ => %{
      encoding: ?1,
      bitmap:
        defbitmap([
          "      ",
          "  XX  ",
          "  XX  ",
          "XXXXXX",
          "  XX  ",
          "  XX  ",
          "      "
        ])
    },
    ?, => %{
      encoding: ?,,
      bb_y_off: -1,
      bitmap:
        defbitmap([
          " XX",
          "XX "
        ])
    },
    ?- => %{
      encoding: ?-,
      bitmap:
        defbitmap([
          "XXXX",
          "    ",
          "    ",
          "    "
        ])
    },
    ?. => %{
      encoding: ?.,
      bitmap:
        defbitmap([
          "XX"
        ])
    },
    ?/ => %{
      encoding: ?/,
      bitmap:
        defbitmap([
          "    XX",
          "    XX",
          "   XX ",
          "  XX  ",
          " XX   ",
          "XX    ",
          "XX    "
        ])
    },
    ?0 => %{
      encoding: ?0,
      bitmap:
        defbitmap([
          " XXXX ",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          " XXXX "
        ])
    },
    ?1 => %{
      encoding: ?1,
      bitmap:
        defbitmap([
          " XX ",
          "XXX ",
          " XX ",
          " XX ",
          " XX ",
          " XX ",
          "XXXX"
        ])
    },
    ?2 => %{
      encoding: ?2,
      bitmap:
        defbitmap([
          " XXXX ",
          "XX  XX",
          "   XX ",
          "  XX  ",
          " XX   ",
          "XX    ",
          "XXXXXX"
        ])
    },
    ?3 => %{
      encoding: ?3,
      bitmap:
        defbitmap([
          " XXXX ",
          "XX  XX",
          "    XX",
          "   XX ",
          "    XX",
          "XX  XX",
          " XXXX "
        ])
    },
    ?4 => %{
      encoding: ?4,
      bitmap:
        defbitmap([
          "XX    ",
          "XX  XX",
          "XX  XX",
          "XXXXXX",
          "    XX",
          "    XX",
          "    XX"
        ])
    },
    ?5 => %{
      encoding: ?5,
      bitmap:
        defbitmap([
          "XXXXXX",
          "XX    ",
          "XXXXX ",
          "    XX",
          "    XX",
          "XX  XX",
          " XXXX "
        ])
    },
    ?6 => %{
      encoding: ?6,
      bitmap:
        defbitmap([
          " XXXX ",
          "XX  XX",
          "XX    ",
          "XXXXX ",
          "XX  XX",
          "XX  XX",
          " XXXX "
        ])
    },
    ?7 => %{
      encoding: ?7,
      bitmap:
        defbitmap([
          "XXXXXX",
          "    XX",
          "   XX ",
          "  XX  ",
          "  XX  ",
          "  XX  ",
          "  XX  "
        ])
    },
    ?8 => %{
      encoding: ?8,
      bitmap:
        defbitmap([
          " XXXX ",
          "XX  XX",
          "XX  XX",
          " XXXX ",
          "XX  XX",
          "XX  XX",
          " XXXX "
        ])
    },
    ?9 => %{
      encoding: ?9,
      bitmap:
        defbitmap([
          " XXXX ",
          "XX  XX",
          "XX  XX",
          " XXXXX",
          "    XX",
          "XX  XX",
          " XXXX "
        ])
    },
    ?: => %{
      encoding: ?:,
      bitmap:
        defbitmap([
          "XX",
          "  ",
          "XX",
          "  ",
          "  "
        ])
    },
    ?; => %{
      encoding: ?;,
      bitmap:
        defbitmap([
          " XX",
          "   ",
          " XX",
          " XX",
          "XX "
        ])
    },
    ?< => %{
      encoding: ?<,
      name: "less-than sign",
      bitmap:
        defbitmap([
          "     ",
          "  XX ",
          " XX  ",
          "XX   ",
          " XX  ",
          "  XX ",
          "     "
        ])
    },
    ?= => %{
      encoding: ?=,
      bitmap:
        defbitmap([
          "XXXXXX",
          "      ",
          "XXXXXX",
          "      ",
          "      "
        ])
    },
    ?> => %{
      encoding: ?>,
      bitmap:
        defbitmap([
          "     ",
          " XX  ",
          "  XX ",
          "   XX",
          "  XX ",
          " XX  ",
          "     "
        ])
    },
    ?? => %{
      encoding: ??,
      bitmap:
        defbitmap([
          " XXXX ",
          "XX  XX",
          "   XX ",
          "  XX  ",
          "  XX  ",
          "      ",
          "  XX  "
        ])
    },
    ?@ => %{
      encoding: ?@,
      bitmap:
        defbitmap([
          "  XXXXXXXX  ",
          " XX      XX ",
          "XX  XX X  XX",
          "XX XX XX  XX",
          "XX  XX XXXX ",
          " XX         ",
          "  XXXXXXX   "
        ])
    },
    ?A => %{
      encoding: ?A,
      bitmap:
        defbitmap([
          " XXXX ",
          "XX  XX",
          "XX  XX",
          "XXXXXX",
          "XX  XX",
          "XX  XX",
          "XX  XX"
        ])
    },
    ?B => %{
      encoding: ?B,
      bitmap:
        defbitmap([
          "XXXXX ",
          "XX  XX",
          "XX  XX",
          "XXXXX ",
          "XX  XX",
          "XX  XX",
          "XXXXX "
        ])
    },
    ?C => %{
      encoding: ?C,
      bitmap:
        defbitmap([
          " XXXXX",
          "XX    ",
          "XX    ",
          "XX    ",
          "XX    ",
          "XX    ",
          " XXXXX"
        ])
    },
    ?D => %{
      encoding: ?D,
      bitmap:
        defbitmap([
          "XXXXX ",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XXXXX "
        ])
    },
    ?E => %{
      encoding: ?E,
      bitmap:
        defbitmap([
          "XXXXXX",
          "XX    ",
          "XX    ",
          "XXXX  ",
          "XX    ",
          "XX    ",
          "XXXXXX"
        ])
    },
    ?F => %{
      encoding: ?F,
      bitmap:
        defbitmap([
          "XXXXXX",
          "XX    ",
          "XX    ",
          "XXXX  ",
          "XX    ",
          "XX    ",
          "XX    "
        ])
    },
    ?G => %{
      encoding: ?G,
      bitmap:
        defbitmap([
          " XXXX ",
          "XX  XX",
          "XX    ",
          "XX XXX",
          "XX  XX",
          "XX  XX",
          " XXXX "
        ])
    },
    ?H => %{
      encoding: ?H,
      bitmap:
        defbitmap([
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XXXXXX",
          "XX  XX",
          "XX  XX",
          "XX  XX"
        ])
    },
    ?I => %{
      encoding: ?I,
      bitmap:
        defbitmap([
          "XXXX",
          " XX ",
          " XX ",
          " XX ",
          " XX ",
          " XX ",
          "XXXX"
        ])
    },
    ?J => %{
      encoding: ?J,
      bitmap:
        defbitmap([
          "    XX",
          "    XX",
          "    XX",
          "    XX",
          "    XX",
          "XX  XX",
          " XXXX "
        ])
    },
    ?K => %{
      encoding: ?K,
      bitmap:
        defbitmap([
          "XX   XX",
          "XX  XX ",
          "XX XX  ",
          "XXXX   ",
          "XX XX  ",
          "XX  XX ",
          "XX   XX"
        ])
    },
    ?L => %{
      encoding: ?L,
      bitmap:
        defbitmap([
          "XX    ",
          "XX    ",
          "XX    ",
          "XX    ",
          "XX    ",
          "XX    ",
          "XXXXXX"
        ])
    },
    ?M => %{
      encoding: ?M,
      bitmap:
        defbitmap([
          "XX   XX",
          "XXX XXX",
          "XXXXXXX",
          "XX X XX",
          "XX   XX",
          "XX   XX",
          "XX   XX"
        ])
    },
    ?N => %{
      encoding: ?N,
      bitmap:
        defbitmap([
          "XX   XX",
          "XXX  XX",
          "XXXX XX",
          "XX XXXX",
          "XX  XXX",
          "XX   XX",
          "XX   XX"
        ])
    },
    ?O => %{
      encoding: ?O,
      bitmap:
        defbitmap([
          " XXXX ",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          " XXXX "
        ])
    },
    ?P => %{
      encoding: ?P,
      bitmap:
        defbitmap([
          "XXXXX ",
          "XX  XX",
          "XX  XX",
          "XXXXX ",
          "XX    ",
          "XX    ",
          "XX    "
        ])
    },
    ?Q => %{
      encoding: ?Q,
      bitmap:
        defbitmap([
          " XXXX ",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XX XX ",
          " XX XX"
        ])
    },
    ?R => %{
      encoding: ?R,
      bitmap:
        defbitmap([
          "XXXXX ",
          "XX  XX",
          "XX  XX",
          "XXXXX ",
          "XX XX ",
          "XX  XX",
          "XX  XX"
        ])
    },
    ?S => %{
      encoding: ?S,
      bitmap:
        defbitmap([
          " XXXX ",
          "XX  XX",
          "XX    ",
          " XXXX ",
          "    XX",
          "XX  XX",
          " XXXX "
        ])
    },
    ?T => %{
      encoding: ?T,
      bitmap:
        defbitmap([
          "XXXXXX",
          "  XX  ",
          "  XX  ",
          "  XX  ",
          "  XX  ",
          "  XX  ",
          "  XX  "
        ])
    },
    ?U => %{
      encoding: ?U,
      bitmap:
        defbitmap([
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          " XXXX "
        ])
    },
    ?V => %{
      encoding: ?V,
      bitmap:
        defbitmap([
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          " XXXX ",
          "  XX  "
        ])
    },
    ?W => %{
      encoding: ?W,
      bitmap:
        defbitmap([
          "XX   XX",
          "XX   XX",
          "XX   XX",
          "XX   XX",
          "XX X XX",
          "XXX XXX",
          "XX   XX"
        ])
    },
    ?X => %{
      encoding: ?X,
      bitmap:
        defbitmap([
          "XX  XX",
          "XX  XX",
          " XXXX ",
          "  XX  ",
          " XXXX ",
          "XX  XX",
          "XX  XX"
        ])
    },
    ?Y => %{
      encoding: ?Y,
      bitmap:
        defbitmap([
          "XX  XX",
          "XX  XX",
          "XX  XX",
          " XXXX ",
          "  XX  ",
          "  XX  ",
          "  XX  "
        ])
    },
    ?Z => %{
      encoding: ?Z,
      bitmap:
        defbitmap([
          "XXXXXX",
          "    XX",
          "   XX ",
          "  XX  ",
          " XX   ",
          "XX    ",
          "XXXXXX"
        ])
    },
    ?[ => %{
      encoding: ?[,
      bitmap:
        defbitmap([
          "XXXX",
          "XX  ",
          "XX  ",
          "XX  ",
          "XX  ",
          "XX  ",
          "XXXX"
        ])
    },
    ?\\ => %{
      encoding: ?\\,
      bitmap:
        defbitmap([
          "XX    ",
          "XX    ",
          " XX   ",
          "  XX  ",
          "   XX ",
          "    XX",
          "    XX"
        ])
    },
    ?] => %{
      encoding: ?],
      bitmap:
        defbitmap([
          "XXXX",
          "  XX",
          "  XX",
          "  XX",
          "  XX",
          "  XX",
          "XXXX"
        ])
    },
    ?^ => %{
      encoding: ?^,
      bitmap:
        defbitmap([
          "  XX  ",
          " XXXX ",
          "XX  XX",
          "     ",
          "     ",
          "     ",
          "     "
        ])
    },
    ?_ => %{
      encoding: ?_,
      bitmap:
        defbitmap([
          "XXXXX"
        ])
    },
    ?` => %{
      encoding: ?`,
      bitmap:
        defbitmap([
          "XX ",
          " XX",
          "   ",
          "   ",
          "   ",
          "   ",
          "   "
        ])
    },
    ?a => %{
      encoding: ?a,
      bitmap:
        defbitmap([
          " XXXXX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          " XXXXX"
        ])
    },
    ?b => %{
      encoding: ?b,
      bitmap:
        defbitmap([
          "XX    ",
          "XX    ",
          "XXXXX ",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XXXXX "
        ])
    },
    ?c => %{
      encoding: ?c,
      bitmap:
        defbitmap([
          " XXXXX",
          "XX    ",
          "XX    ",
          "XX    ",
          " XXXXX"
        ])
    },
    ?d => %{
      encoding: ?d,
      bitmap:
        defbitmap([
          "    XX",
          "    XX",
          " XXXXX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          " XXXXX"
        ])
    },
    ?e => %{
      encoding: ?e,
      bitmap:
        defbitmap([
          " XXXX ",
          "XX  XX",
          "XXXXXX",
          "XX    ",
          " XXXXX"
        ])
    },
    ?f => %{
      encoding: ?f,
      bitmap:
        defbitmap([
          "  XXX",
          " XX  ",
          " XX  ",
          "XXXXX",
          " XX  ",
          " XX  ",
          " XX  "
        ])
    },
    ?g => %{
      encoding: ?g,
      bitmap:
        defbitmap([
          " XXXXX",
          "XX  XX",
          " XXXXX",
          "    XX",
          "XXXXX "
        ])
    },
    ?h => %{
      encoding: ?h,
      bitmap:
        defbitmap([
          "XX    ",
          "XX    ",
          "XXXXX ",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XX  XX"
        ])
    },
    ?i => %{
      encoding: ?i,
      bitmap:
        defbitmap([
          "XX",
          "  ",
          "XX",
          "XX",
          "XX",
          "XX",
          "XX"
        ])
    },
    ?j => %{
      encoding: ?j,
      bitmap:
        defbitmap([
          "   XX",
          "     ",
          "   XX",
          "   XX",
          "   XX",
          "XX XX",
          " XXX "
        ])
    },
    ?k => %{
      encoding: ?k,
      bitmap:
        defbitmap([
          "XX    ",
          "XX XX ",
          "XXXX  ",
          "XXXX  ",
          "XXXX  ",
          "XX XX ",
          "XX  XX"
        ])
    },
    ?l => %{
      encoding: ?l,
      bitmap:
        defbitmap([
          "XX",
          "XX",
          "XX",
          "XX",
          "XX",
          "XX",
          "XX"
        ])
    },
    ?m => %{
      encoding: ?m,
      bitmap:
        defbitmap([
          "XXX XXX ",
          "XX XX XX",
          "XX XX XX",
          "XX XX XX",
          "XX XX XX"
        ])
    },
    ?n => %{
      encoding: ?n,
      bitmap:
        defbitmap([
          "XXXXX ",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XX  XX"
        ])
    },
    ?o => %{
      encoding: ?o,
      bitmap:
        defbitmap([
          " XXXX ",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          " XXXX "
        ])
    },
    ?p => %{
      encoding: ?p,
      bitmap:
        defbitmap([
          "XXXXX ",
          "XX  XX",
          "XXXXX ",
          "XX    ",
          "XX    "
        ])
    },
    ?q => %{
      encoding: ?q,
      bitmap:
        defbitmap([
          " XXXXX",
          "XX  XX",
          " XXXXX",
          "    XX",
          "    XX"
        ])
    },
    ?r => %{
      encoding: ?r,
      bitmap:
        defbitmap([
          " XXXX",
          "XX   ",
          "XX   ",
          "XX   ",
          "XX   "
        ])
    },
    ?s => %{
      encoding: ?s,
      bitmap:
        defbitmap([
          " XXXXX",
          "XX    ",
          " XXXX ",
          "    XX",
          "XXXXX "
        ])
    },
    ?t => %{
      encoding: ?t,
      bitmap:
        defbitmap([
          " XX ",
          " XX ",
          "XXXX",
          " XX ",
          " XX ",
          " XX ",
          " XX "
        ])
    },
    ?u => %{
      encoding: ?u,
      bitmap:
        defbitmap([
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          " XXXX "
        ])
    },
    ?v => %{
      encoding: ?v,
      bitmap:
        defbitmap([
          "XX  XX",
          "XX  XX",
          "XX  XX",
          " XXXX ",
          "  XX  "
        ])
    },
    ?w => %{
      encoding: ?w,
      bitmap:
        defbitmap([
          "XX    XX",
          "XX    XX",
          "XX XX XX",
          "XX XX XX",
          " XX  XX "
        ])
    },
    ?x => %{
      encoding: ?x,
      bitmap:
        defbitmap([
          "XX  XX",
          " XXXX ",
          "  XX  ",
          " XXXX ",
          "XX  XX"
        ])
    },
    ?y => %{
      encoding: ?y,
      bitmap:
        defbitmap([
          "XX  XX",
          "XX  XX",
          " XXXXX",
          "    XX",
          "XXXXX "
        ])
    },
    ?z => %{
      encoding: ?z,
      bitmap:
        defbitmap([
          "XXXXXX",
          "   XX ",
          "  XX  ",
          " XX   ",
          "XXXXXX"
        ])
    },
    ?{ => %{
      encoding: ?{,
      bitmap:
        defbitmap([
          "  XX",
          " XX ",
          " XX ",
          "XX  ",
          " XX ",
          " XX ",
          "  XX"
        ])
    },
    ?| => %{
      encoding: ?|,
      bitmap:
        defbitmap([
          "XX",
          "XX",
          "XX",
          "XX",
          "XX",
          "XX",
          "XX"
        ])
    },
    ?} => %{
      encoding: ?},
      bitmap:
        defbitmap([
          "XX  ",
          " XX ",
          " XX ",
          "  XX",
          " XX ",
          " XX ",
          "XX  "
        ])
    },
    ?~ => %{
      encoding: ?~,
      bitmap:
        defbitmap([
          " XX    ",
          "XX X XX",
          "    XX ",
          "       ",
          "       "
        ])
    },

    # ISO 8859-1 CHARACTERS

    160 => %{
      encoding: 160,
      name: "no-break space",
      bitmap:
        defbitmap([
          "  ",
          "  ",
          "  ",
          "  ",
          "  ",
          "  ",
          "  "
        ])
    },
    ?¡ => %{
      encoding: ?¡,
      name: "inverted exclamation mark",
      bitmap:
        defbitmap([
          "XX",
          "  ",
          "XX",
          "XX",
          "XX",
          "XX",
          "XX"
        ])
    },
    ?¢ => %{
      encoding: ?¢,
      name: "cent sign",
      bitmap:
        defbitmap([
          "  XXXX",
          " XX   ",
          "XXXXX ",
          " XX   ",
          "  XXXX",
          "      "
        ])
    },
    ?£ => %{
      encoding: ?£,
      name: "pound sign",
      bitmap:
        defbitmap([
          "  XXXX",
          " XX   ",
          " XX   ",
          "XXXXX ",
          " XX   ",
          " XX   ",
          "XXXXXX"
        ])
    },
    ?¤ => %{
      encoding: ?¤,
      name: "currency sign",
      bitmap:
        defbitmap([
          "     ",
          "XX  XX",
          " XXXX ",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          " XXXX ",
          "XX  XX"
        ])
    },
    ?¥ => %{
      encoding: ?¥,
      name: "yen sign",
      bitmap:
        defbitmap([
          "XX  XX",
          " XXXX ",
          "XXXXXX",
          "  XX  ",
          "XXXXXX",
          "  XX  ",
          "  XX  "
        ])
    },
    ?¦ => %{
      encoding: ?¦,
      name: "broken bar",
      bitmap:
        defbitmap([
          "XX",
          "XX",
          "XX",
          "  ",
          "XX",
          "XX",
          "XX"
        ])
    },
    ?§ => %{
      encoding: ?§,
      name: "section sign",
      bb_y_off: -1,
      bitmap:
        defbitmap([
          " XXX ",
          "X    ",
          " X   ",
          " XXX ",
          "X   X",
          " XXX ",
          "   X ",
          "    X",
          " XXX "
        ])
    },
    ?ß => %{
      encoding: ?ß,
      bb_y_off: -1,
      bitmap:
        defbitmap([
          " XXXXX ",
          "XX   XX",
          "XX  XX ",
          "XX XX  ",
          "XX  XX ",
          "XX   XX",
          "XX XXX ",
          "XX     "
        ])
    },
    ?Ä => %{
      encoding: ?Ä,
      bitmap:
        defbitmap([
          "      ",
          "XX  XX",
          "      ",
          " XXXX ",
          "XX  XX",
          "XXXXXX",
          "XX  XX",
          "XX  XX"
        ])
    },
    ?Á => %{
      encoding: ?Á,
      bitmap:
        defbitmap([
          "   XX ",
          "  XX  ",
          "      ",
          " XXXX ",
          "XX  XX",
          "XXXXXX",
          "XX  XX",
          "XX  XX"
        ])
    },
    ?À => %{
      encoding: ?À,
      bitmap:
        defbitmap([
          " XX   ",
          "  XX  ",
          "      ",
          " XXXX ",
          "XX  XX",
          "XXXXXX",
          "XX  XX",
          "XX  XX"
        ])
    },
    ?Å => %{
      encoding: ?Å,
      bitmap:
        defbitmap([
          " XXXX ",
          " XXXX ",
          "      ",
          " XXXX ",
          "XX  XX",
          "XXXXXX",
          "XX  XX",
          "XX  XX"
        ])
    },
    ?Ã => %{
      encoding: ?Ã,
      bitmap:
        defbitmap([
          " XX XX",
          "XX XX ",
          "      ",
          " XXXX ",
          "XX  XX",
          "XXXXXX",
          "XX  XX",
          "XX  XX"
        ])
    },
    ?ä => %{
      encoding: ?ä,
      bitmap:
        defbitmap([
          "XX  XX",
          "      ",
          " XXXXX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          " XXXXX"
        ])
    },
    ?Ö => %{
      encoding: ?Ö,
      bitmap:
        defbitmap([
          "XX  XX",
          "      ",
          " XXXX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          " XXXX "
        ])
    },
    ?ö => %{
      encoding: ?ö,
      bitmap:
        defbitmap([
          "XX  XX",
          "      ",
          " XXXX ",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          " XXXX "
        ])
    },
    ?Ü => %{
      encoding: ?Ü,
      bitmap:
        defbitmap([
          "XX  XX",
          "      ",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          " XXXX "
        ])
    },
    ?ü => %{
      encoding: ?ü,
      bitmap:
        defbitmap([
          "XX  XX",
          "      ",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          "XX  XX",
          " XXXX "
        ])
    },
    ?¨ => %{
      encoding: ?¨,
      name: "diaresis",
      bitmap:
        defbitmap([
          "XX  XX",
          "      ",
          "      ",
          "      ",
          "      ",
          "      ",
          "      "
        ])
    },
    ?© => %{
      encoding: ?©,
      name: "copyright sign",
      bb_y_off: -1,
      bitmap:
        defbitmap([
          " XXX ",
          "X   X",
          "  X  ",
          " X X ",
          " X   ",
          " X X ",
          "  X  ",
          "X   X",
          " XXX "
        ])
    },
    ?€ => %{
      encoding: ?€,
      name: "euro sign",
      bitmap:
        defbitmap([
          "  XXX",
          " X   ",
          "XXXX ",
          " X   ",
          "XXXX ",
          " X   ",
          "  XXX"
        ])
    },
    ?¯ => %{
      encoding: ?¯,
      name: "macron",
      bitmap:
        defbitmap([
          "XXXXX",
          "     ",
          "     ",
          "     ",
          "     ",
          "     ",
          "     "
        ])
    },
    ?° => %{
      encoding: ?°,
      name: "degree sign",
      bitmap:
        defbitmap([
          " X ",
          "X X",
          " X ",
          "   ",
          "   ",
          "   ",
          "   "
        ])
    },
    ?± => %{
      encoding: ?±,
      name: "plus-minus sign",
      bitmap:
        defbitmap([
          "  X  ",
          "  X  ",
          "XXXXX",
          "  X  ",
          "  X  ",
          "     ",
          "XXXXX"
        ])
    },
    ?² => %{
      encoding: ?²,
      name: "superscript two",
      bitmap:
        defbitmap([
          "XX ",
          "  X",
          " X ",
          "X  ",
          "XXX",
          "   ",
          "   "
        ])
    },
    ?³ => %{
      encoding: ?³,
      name: "superscript three",
      bitmap:
        defbitmap([
          "XX ",
          "  X",
          " X ",
          "  X",
          "XX ",
          "   ",
          "   "
        ])
    },
    ?´ => %{
      encoding: ?´,
      name: "acute accent",
      bb_y_off: 5,
      bitmap:
        defbitmap([
          " X",
          "X "
        ])
    },
    ?µ => %{
      encoding: ?µ,
      name: "micro sign",
      bb_y_off: -1,
      bitmap:
        defbitmap([
          "    ",
          "    ",
          "    ",
          "   X",
          "X  X",
          "X  X",
          "XXX ",
          "X   ",
          "X   "
        ])
    },
    ?· => %{
      encoding: ?·,
      name: "middle dot",
      bitmap:
        defbitmap([
          " ",
          " ",
          " ",
          "X",
          " ",
          " ",
          " "
        ])
    },
    ?¹ => %{
      encoding: ?¹,
      name: "superscript one",
      bitmap:
        defbitmap([
          " X ",
          "XX ",
          " X ",
          " X ",
          "XXX",
          "   ",
          "   "
        ])
    },
    ?ª => %{
      encoding: ?ª,
      name: "feminine ordinal indicator",
      bitmap:
        defbitmap([
          " X ",
          "X X",
          "XXX",
          "X X",
          "   ",
          "   ",
          "   "
        ])
    },
    ?º => %{
      encoding: ?º,
      name: "masculine ordinal indicator",
      bitmap:
        defbitmap([
          " X ",
          "X X",
          "X X",
          " X ",
          "   ",
          "   ",
          "   "
        ])
    },
    ?« => %{
      encoding: ?«,
      name: "left-pointing double angle quotation mark",
      bitmap:
        defbitmap([
          "     ",
          "     ",
          " X X ",
          "X X  ",
          " X X ",
          "     ",
          "     "
        ])
    },
    ?¬ => %{
      encoding: ?¬,
      name: "not sign",
      bitmap:
        defbitmap([
          "     ",
          "     ",
          "     ",
          "XXXXX",
          "    X",
          "     ",
          "     "
        ])
    },
    ?» => %{
      encoding: ?»,
      name: "right-pointing double angle quotation mark",
      bitmap:
        defbitmap([
          "     ",
          "     ",
          " X X ",
          "  X X",
          " X X ",
          "     ",
          "     "
        ])
    },
    ?¼ => %{
      encoding: ?¼,
      name: "vulgar fraction one quarter",
      bitmap:
        defbitmap([
          " X      X   ",
          "XX     X    ",
          " X    X X  X",
          " X   X  X  X",
          " X  X   XXXX",
          "   X       X",
          "  X        X"
        ])
    },
    ?½ => %{
      encoding: ?½,
      name: "vulgar fraction one half",
      bitmap:
        defbitmap([
          " X      X   ",
          "XX     X    ",
          " X    X  XX ",
          " X   X  X  X",
          " X  X     X ",
          "   X     X  ",
          "  X     XXXX"
        ])
    },
    ?¾ => %{
      encoding: ?¾,
      name: "vulgar fraction three quarters",
      bitmap:
        defbitmap([
          " XX      X    ",
          "X  X    X     ",
          "  X    X  X  X",
          "X  X  X   X  X",
          " XX  X    XXXX",
          "    X        X",
          "   X         X"
        ])
    },
    ?¿ => %{
      encoding: ?¿,
      bitmap:
        defbitmap([
          "  X  ",
          "     ",
          "  X  ",
          "  X  ",
          "   X ",
          "X   X",
          " XXX "
        ])
    }
  }

  @font %Font{
    name: "BlinkenLightsRegular",
    variants: [
      @characters
      |> Map.new(fn {encoding, char} ->
        {encoding, char.bitmap}
      end)
    ]
  }

  def get(), do: @font
end
