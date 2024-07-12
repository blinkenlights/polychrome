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
          "XXXXX",
          "X   X",
          "X   X",
          "X   X",
          "X   X",
          "X   X",
          "XXXXX"
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
          "X",
          "X",
          "X",
          "X",
          "X",
          " ",
          "X"
        ])
    },
    ?" => %{
      encoding: ?",
      bitmap:
        defbitmap([
          "X X",
          "X X",
          "   ",
          "   ",
          "   ",
          "   ",
          "   "
        ])
    },
    ?# => %{
      encoding: ?#,
      bitmap:
        defbitmap([
          " X X ",
          " X X ",
          "XXXXX",
          " X X ",
          "XXXXX",
          " X X ",
          " X X "
        ])
    },
    ?$ => %{
      encoding: ?$,
      bitmap:
        defbitmap([
          "  X  ",
          " XXXX",
          "X X  ",
          " XXX ",
          "  X X",
          "XXXX ",
          "  X  "
        ])
    },
    ?% => %{
      encoding: ?%,
      bitmap:
        defbitmap([
          "XX  X",
          "XX  X",
          "   X ",
          "  X  ",
          " X   ",
          "X  XX",
          "X  XX"
        ])
    },
    ?& => %{
      encoding: ?&,
      bitmap:
        defbitmap([
          " XX  ",
          "X  X ",
          "X  X ",
          " XX  ",
          "X X X",
          "X  X ",
          " XX X"
        ])
    },
    ?' => %{
      encoding: ?',
      bitmap:
        defbitmap([
          "X",
          "X",
          " ",
          " ",
          " ",
          " ",
          " "
        ])
    },
    ?( => %{
      encoding: ?(,
      bitmap:
        defbitmap([
          "  X",
          " X ",
          "X  ",
          "X  ",
          "X  ",
          " X ",
          "  X"
        ])
    },
    ?) => %{
      encoding: ?),
      bitmap:
        defbitmap([
          "X  ",
          " X ",
          "  X",
          "  X",
          "  X",
          " X ",
          "X  "
        ])
    },
    ?* => %{
      encoding: ?*,
      bitmap:
        defbitmap([
          "     ",
          "X X X",
          " XXX ",
          "XXXXX",
          " XXX ",
          "X X X",
          "     "
        ])
    },
    ?+ => %{
      encoding: ?1,
      bitmap:
        defbitmap([
          "     ",
          "  X  ",
          "  X  ",
          "XXXXX",
          "  X  ",
          "  X  ",
          "     "
        ])
    },
    ?, => %{
      encoding: ?,,
      bb_y_off: -1,
      bitmap:
        defbitmap([
          " X",
          "X "
        ])
    },
    ?- => %{
      encoding: ?-,
      bitmap:
        defbitmap([
          "   ",
          "   ",
          "   ",
          "XXX",
          "   ",
          "   ",
          "   "
        ])
    },
    ?. => %{
      encoding: ?.,
      bitmap:
        defbitmap([
          "X"
        ])
    },
    ?/ => %{
      encoding: ?/,
      bitmap:
        defbitmap([
          "    X",
          "    X",
          "   X ",
          "  X  ",
          " X   ",
          "X    ",
          "X    "
        ])
    },
    ?0 => %{
      encoding: ?0,
      bitmap:
        defbitmap([
          " XXX ",
          "X   X",
          "X   X",
          "X   X",
          "X   X",
          "X   X",
          " XXX "
        ])
    },
    ?1 => %{
      encoding: ?1,
      bitmap:
        defbitmap([
          " X ",
          "XX ",
          " X ",
          " X ",
          " X ",
          " X ",
          "XXX"
        ])
    },
    ?2 => %{
      encoding: ?2,
      bitmap:
        defbitmap([
          " XXX ",
          "X   X",
          "   X ",
          "  X  ",
          " X   ",
          "X    ",
          "XXXXX"
        ])
    },
    ?3 => %{
      encoding: ?3,
      bitmap:
        defbitmap([
          " XXX ",
          "X   X",
          "    X",
          "   X ",
          "    X",
          "X   X",
          " XXX "
        ])
    },
    ?4 => %{
      encoding: ?4,
      bitmap:
        defbitmap([
          "X    ",
          "X   X",
          "X   X",
          "XXXXX",
          "    X",
          "    X",
          "    X"
        ])
    },
    ?5 => %{
      encoding: ?5,
      bitmap:
        defbitmap([
          "XXXXX",
          "X    ",
          "XXXX ",
          "    X",
          "    X",
          "X   X",
          " XXX "
        ])
    },
    ?6 => %{
      encoding: ?6,
      bitmap:
        defbitmap([
          " XXX ",
          "X   X",
          "X    ",
          "XXXX ",
          "X   X",
          "X   X",
          " XXX "
        ])
    },
    ?7 => %{
      encoding: ?7,
      bitmap:
        defbitmap([
          "XXXXX",
          "    X",
          "   X ",
          "  X  ",
          "  X  ",
          "  X  ",
          "  X  "
        ])
    },
    ?8 => %{
      encoding: ?8,
      bitmap:
        defbitmap([
          " XXX ",
          "X   X",
          "X   X",
          " XXX ",
          "X   X",
          "X   X",
          " XXX "
        ])
    },
    ?9 => %{
      encoding: ?9,
      bitmap:
        defbitmap([
          " XXX ",
          "X   X",
          "X   X",
          " XXXX",
          "    X",
          "X   X",
          " XXX "
        ])
    },
    ?: => %{
      encoding: ?:,
      bitmap:
        defbitmap([
          " ",
          "X",
          " ",
          "X",
          " ",
          " "
        ])
    },
    ?; => %{
      encoding: ?;,
      bitmap:
        defbitmap([
          "  ",
          " X",
          "  ",
          " X",
          " X",
          "X "
        ])
    },
    ?< => %{
      encoding: ?<,
      name: "less-than sign",
      bitmap:
        defbitmap([
          "    ",
          "  X ",
          " X  ",
          "X   ",
          " X  ",
          "  X ",
          "    "
        ])
    },
    ?= => %{
      encoding: ?=,
      bitmap:
        defbitmap([
          "     ",
          "     ",
          "XXXXX",
          "     ",
          "XXXXX",
          "     ",
          "     "
        ])
    },
    ?> => %{
      encoding: ?>,
      bitmap:
        defbitmap([
          "    ",
          " X  ",
          "  X ",
          "   X",
          "  X ",
          " X  ",
          "    "
        ])
    },
    ?? => %{
      encoding: ??,
      bitmap:
        defbitmap([
          " XXX ",
          "X   X",
          "   X ",
          "  X  ",
          "  X  ",
          "     ",
          "  X  "
        ])
    },
    ?@ => %{
      encoding: ?@,
      bitmap:
        defbitmap([
          "  XXXXXX  ",
          " X      X ",
          "X  XX X  X",
          "X X  XX  X",
          "X  XX XXX ",
          " X        ",
          "  XXXXXX  "
        ])
    },
    ?A => %{
      encoding: ?A,
      bitmap:
        defbitmap([
          " XXX ",
          "X   X",
          "X   X",
          "XXXXX",
          "X   X",
          "X   X",
          "X   X"
        ])
    },
    ?B => %{
      encoding: ?B,
      bitmap:
        defbitmap([
          "XXXX ",
          "X   X",
          "X   X",
          "XXXX ",
          "X   X",
          "X   X",
          "XXXX "
        ])
    },
    ?C => %{
      encoding: ?C,
      bitmap:
        defbitmap([
          " XXXX",
          "X    ",
          "X    ",
          "X    ",
          "X    ",
          "X    ",
          " XXXX"
        ])
    },
    ?D => %{
      encoding: ?D,
      bitmap:
        defbitmap([
          "XXXX ",
          "X   X",
          "X   X",
          "X   X",
          "X   X",
          "X   X",
          "XXXX "
        ])
    },
    ?E => %{
      encoding: ?E,
      bitmap:
        defbitmap([
          "XXXXX",
          "X    ",
          "X    ",
          "XXX  ",
          "X    ",
          "X    ",
          "XXXXX"
        ])
    },
    ?F => %{
      encoding: ?F,
      bitmap:
        defbitmap([
          "XXXXX",
          "X    ",
          "X    ",
          "XXX  ",
          "X    ",
          "X    ",
          "X    "
        ])
    },
    ?G => %{
      encoding: ?G,
      bitmap:
        defbitmap([
          " XXX ",
          "X   X",
          "X    ",
          "X XXX",
          "X   X",
          "X   X",
          " XXX "
        ])
    },
    ?H => %{
      encoding: ?H,
      bitmap:
        defbitmap([
          "X   X",
          "X   X",
          "X   X",
          "XXXXX",
          "X   X",
          "X   X",
          "X   X"
        ])
    },
    ?I => %{
      encoding: ?I,
      bitmap:
        defbitmap([
          "XXX",
          " X ",
          " X ",
          " X ",
          " X ",
          " X ",
          "XXX"
        ])
    },
    ?J => %{
      encoding: ?J,
      bitmap:
        defbitmap([
          "    X",
          "    X",
          "    X",
          "    X",
          "    X",
          "X   X",
          " XXX "
        ])
    },
    ?K => %{
      encoding: ?K,
      bitmap:
        defbitmap([
          "X   X",
          "X  X ",
          "X X  ",
          "XX   ",
          "X X  ",
          "X  X ",
          "X   X"
        ])
    },
    ?L => %{
      encoding: ?L,
      bitmap:
        defbitmap([
          "X    ",
          "X    ",
          "X    ",
          "X    ",
          "X    ",
          "X    ",
          "XXXXX"
        ])
    },
    ?M => %{
      encoding: ?M,
      bitmap:
        defbitmap([
          "X   X",
          "XX XX",
          "X X X",
          "X   X",
          "X   X",
          "X   X",
          "X   X"
        ])
    },
    ?N => %{
      encoding: ?N,
      bitmap:
        defbitmap([
          "X   X",
          "X   X",
          "XX  X",
          "X X X",
          "X  XX",
          "X   X",
          "X   X"
        ])
    },
    ?O => %{
      encoding: ?O,
      bitmap:
        defbitmap([
          " XXX ",
          "X   X",
          "X   X",
          "X   X",
          "X   X",
          "X   X",
          " XXX "
        ])
    },
    ?P => %{
      encoding: ?P,
      bitmap:
        defbitmap([
          "XXXX ",
          "X   X",
          "X   X",
          "XXXX ",
          "X    ",
          "X    ",
          "X    "
        ])
    },
    ?Q => %{
      encoding: ?Q,
      bitmap:
        defbitmap([
          " XXX ",
          "X   X",
          "X   X",
          "X   X",
          "X   X",
          "X  X ",
          " XX X"
        ])
    },
    ?R => %{
      encoding: ?R,
      bitmap:
        defbitmap([
          "XXXX ",
          "X   X",
          "X   X",
          "XXXX ",
          "X X  ",
          "X  X ",
          "X   X"
        ])
    },
    ?S => %{
      encoding: ?S,
      bitmap:
        defbitmap([
          " XXX ",
          "X   X",
          "X    ",
          " XXX ",
          "    X",
          "X   X",
          " XXX "
        ])
    },
    ?T => %{
      encoding: ?T,
      bitmap:
        defbitmap([
          "XXXXX",
          "  X  ",
          "  X  ",
          "  X  ",
          "  X  ",
          "  X  ",
          "  X  "
        ])
    },
    ?U => %{
      encoding: ?U,
      bitmap:
        defbitmap([
          "X   X",
          "X   X",
          "X   X",
          "X   X",
          "X   X",
          "X   X",
          " XXX "
        ])
    },
    ?V => %{
      encoding: ?V,
      bitmap:
        defbitmap([
          "X   X",
          "X   X",
          "X   X",
          "X   X",
          "X   X",
          " X X ",
          "  X  "
        ])
    },
    ?W => %{
      encoding: ?W,
      bitmap:
        defbitmap([
          "X   X",
          "X   X",
          "X   X",
          "X   X",
          "X X X",
          "XX XX",
          "X   X"
        ])
    },
    ?X => %{
      encoding: ?X,
      bitmap:
        defbitmap([
          "X   X",
          "X   X",
          " X X ",
          "  X  ",
          " X X ",
          "X   X",
          "X   X"
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
          "XXX",
          "X  ",
          "X  ",
          "X  ",
          "X  ",
          "X  ",
          "XXX"
        ])
    },
    ?\\ => %{
      encoding: ?\\,
      bitmap:
        defbitmap([
          "X    ",
          "X    ",
          " X   ",
          "  X  ",
          "   X ",
          "    X",
          "    X"
        ])
    },
    ?] => %{
      encoding: ?],
      bitmap:
        defbitmap([
          "XXX",
          "  X",
          "  X",
          "  X",
          "  X",
          "  X",
          "XXX"
        ])
    },
    ?^ => %{
      encoding: ?^,
      bitmap:
        defbitmap([
          "  X  ",
          " X X ",
          "X   X",
          "      ",
          "      ",
          "      ",
          "      "
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
          "X ",
          " X",
          "  ",
          "  ",
          "  ",
          "  ",
          "  "
        ])
    },
    ?a => %{
      encoding: ?a,
      bitmap:
        defbitmap([
          " XXXX",
          "X   X",
          "X   X",
          "X   X",
          " XXXX"
        ])
    },
    ?b => %{
      encoding: ?b,
      bitmap:
        defbitmap([
          "X    ",
          "X    ",
          "XXXX ",
          "X   X",
          "X   X",
          "X   X",
          "XXXX "
        ])
    },
    ?c => %{
      encoding: ?c,
      bitmap:
        defbitmap([
          " XXXX",
          "X    ",
          "X    ",
          "X    ",
          " XXXX"
        ])
    },
    ?d => %{
      encoding: ?d,
      bitmap:
        defbitmap([
          "    X",
          "    X",
          " XXXX",
          "X   X",
          "X   X",
          "X   X",
          " XXXX"
        ])
    },
    ?e => %{
      encoding: ?e,
      bitmap:
        defbitmap([
          " XXX ",
          "X   X",
          "XXXXX",
          "X    ",
          " XXXX"
        ])
    },
    ?f => %{
      encoding: ?f,
      bitmap:
        defbitmap([
          "  XX",
          " X  ",
          " X  ",
          "XXXX",
          " X  ",
          " X  ",
          " X  "
        ])
    },
    ?g => %{
      encoding: ?g,
      bitmap:
        defbitmap([
          " XXXX",
          "X   X",
          " XXXX",
          "    X",
          "XXXX "
        ])
    },
    ?h => %{
      encoding: ?h,
      bitmap:
        defbitmap([
          "X    ",
          "X    ",
          "XXXX ",
          "X   X",
          "X   X",
          "X   X",
          "X   X"
        ])
    },
    ?i => %{
      encoding: ?i,
      bitmap:
        defbitmap([
          "X",
          " ",
          "X",
          "X",
          "X",
          "X",
          "X"
        ])
    },
    ?j => %{
      encoding: ?j,
      bitmap:
        defbitmap([
          "   X",
          "    ",
          "   X",
          "   X",
          "   X",
          "X  X",
          " XX "
        ])
    },
    ?k => %{
      encoding: ?k,
      bitmap:
        defbitmap([
          "X   ",
          "X  X",
          "X X ",
          "XX  ",
          "X X ",
          "X  X",
          "X  X"
        ])
    },
    ?l => %{
      encoding: ?l,
      bitmap:
        defbitmap([
          "X",
          "X",
          "X",
          "X",
          "X",
          "X",
          "X"
        ])
    },
    ?m => %{
      encoding: ?m,
      bitmap:
        defbitmap([
          "XXX XX ",
          "X  X  X",
          "X  X  X",
          "X  X  X",
          "X  X  X"
        ])
    },
    ?n => %{
      encoding: ?n,
      bitmap:
        defbitmap([
          "XXXX ",
          "X   X",
          "X   X",
          "X   X",
          "X   X"
        ])
    },
    ?o => %{
      encoding: ?o,
      bitmap:
        defbitmap([
          " XXX ",
          "X   X",
          "X   X",
          "X   X",
          " XXX "
        ])
    },
    ?p => %{
      encoding: ?p,
      bitmap:
        defbitmap([
          "XXXX ",
          "X   X",
          "XXXX ",
          "X    ",
          "X    "
        ])
    },
    ?q => %{
      encoding: ?q,
      bitmap:
        defbitmap([
          " XXXX",
          "X   X",
          " XXXX",
          "    X",
          "    X"
        ])
    },
    ?r => %{
      encoding: ?r,
      bitmap:
        defbitmap([
          " XXX",
          "X   ",
          "X   ",
          "X   ",
          "X   "
        ])
    },
    ?s => %{
      encoding: ?s,
      bitmap:
        defbitmap([
          " XXXX",
          "X    ",
          " XXX ",
          "    X",
          "XXXX "
        ])
    },
    ?t => %{
      encoding: ?t,
      bitmap:
        defbitmap([
          " X ",
          " X ",
          "XXX",
          " X ",
          " X ",
          " X ",
          " X "
        ])
    },
    ?u => %{
      encoding: ?u,
      bitmap:
        defbitmap([
          "X   X",
          "X   X",
          "X   X",
          "X   X",
          " XXX "
        ])
    },
    ?v => %{
      encoding: ?v,
      bitmap:
        defbitmap([
          "X   X",
          "X   X",
          "X   X",
          " X X ",
          "  X  "
        ])
    },
    ?w => %{
      encoding: ?w,
      bitmap:
        defbitmap([
          "X     X",
          "X     X",
          "X  X  X",
          "X  X  X",
          " XX XX "
        ])
    },
    ?x => %{
      encoding: ?x,
      bitmap:
        defbitmap([
          "X   X",
          " X X ",
          "  X  ",
          " X X ",
          "X   X"
        ])
    },
    ?y => %{
      encoding: ?y,
      bitmap:
        defbitmap([
          "X   X",
          "X   X",
          " XXXX",
          "    X",
          "XXXX "
        ])
    },
    ?z => %{
      encoding: ?z,
      bitmap:
        defbitmap([
          "XXXXX",
          "   X ",
          "  X  ",
          " X   ",
          "XXXXX"
        ])
    },
    ?{ => %{
      encoding: ?{,
      bitmap:
        defbitmap([
          "  X",
          " X ",
          " X ",
          "X  ",
          " X ",
          " X ",
          "  X"
        ])
    },
    ?| => %{
      encoding: ?|,
      bitmap:
        defbitmap([
          "X",
          "X",
          "X",
          "X",
          "X",
          "X",
          "X"
        ])
    },
    ?} => %{
      encoding: ?},
      bitmap:
        defbitmap([
          "X  ",
          " X ",
          " X ",
          "  X",
          " X ",
          " X ",
          "X  "
        ])
    },
    ?~ => %{
      encoding: ?~,
      bitmap:
        defbitmap([
          " X   ",
          "X X X",
          "   X ",
          "     ",
          "     "
        ])
    },

    # ISO 8859-1 CHARACTERS

    160 => %{
      encoding: 160,
      name: "no-break space",
      bitmap:
        defbitmap([
          " ",
          " ",
          " ",
          " ",
          " ",
          " ",
          " "
        ])
    },
    ?¡ => %{
      encoding: ?¡,
      name: "inverted exclamation mark",
      bitmap:
        defbitmap([
          "X",
          " ",
          "X",
          "X",
          "X",
          "X",
          "X"
        ])
    },
    ?¢ => %{
      encoding: ?¢,
      name: "cent sign",
      bitmap:
        defbitmap([
          "     ",
          "  XXX",
          " X   ",
          "XXXX ",
          " X   ",
          "  XXX",
          "     "
        ])
    },
    ?£ => %{
      encoding: ?£,
      name: "pound sign",
      bitmap:
        defbitmap([
          "  XXX",
          " X   ",
          " X   ",
          "XXXX ",
          " X   ",
          " X   ",
          "XXXXX"
        ])
    },
    ?¤ => %{
      encoding: ?¤,
      name: "currency sign",
      bitmap:
        defbitmap([
          "     ",
          "X   X",
          " XXX ",
          "X   X",
          "X   X",
          "X   X",
          " XXX ",
          "X   X"
        ])
    },
    ?¥ => %{
      encoding: ?¥,
      name: "yen sign",
      bitmap:
        defbitmap([
          "X   X",
          " X X ",
          "XXXXX",
          "  X  ",
          "XXXXX",
          "  X  ",
          "  X  "
        ])
    },
    ?¦ => %{
      encoding: ?¦,
      name: "broken bar",
      bitmap:
        defbitmap([
          "X",
          "X",
          "X",
          " ",
          "X",
          "X",
          "X"
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
          " XXX ",
          "X   X",
          "X  X ",
          "X X  ",
          "X  X ",
          "X   X",
          "X XX ",
          "X    "
        ])
    },
    ?Ä => %{
      encoding: ?Ä,
      bitmap:
        defbitmap([
          "     ",
          "X   X",
          "     ",
          " XXX ",
          "X   X",
          "XXXXX",
          "X   X",
          "X   X"
        ])
    },
    ?Á => %{
      encoding: ?Á,
      bitmap:
        defbitmap([
          "   X ",
          "  X  ",
          "     ",
          " XXX ",
          "X   X",
          "XXXXX",
          "X   X",
          "X   X"
        ])
    },
    ?À => %{
      encoding: ?À,
      bitmap:
        defbitmap([
          " X   ",
          "  X  ",
          "     ",
          " XXX ",
          "X   X",
          "XXXXX",
          "X   X",
          "X   X"
        ])
    },
    ?Å => %{
      encoding: ?Å,
      bitmap:
        defbitmap([
          " XXX ",
          " XXX ",
          "     ",
          " XXX ",
          "X   X",
          "XXXXX",
          "X   X",
          "X   X"
        ])
    },
    ?Ã => %{
      encoding: ?Ã,
      bitmap:
        defbitmap([
          " XX X",
          "X XX ",
          "     ",
          " XXX ",
          "X   X",
          "XXXXX",
          "X   X",
          "X   X"
        ])
    },
    ?ä => %{
      encoding: ?ä,
      bitmap:
        defbitmap([
          "X   X",
          "     ",
          " XXXX",
          "X   X",
          "X   X",
          "X   X",
          " XXXX"
        ])
    },
    ?Ö => %{
      encoding: ?Ö,
      bitmap:
        defbitmap([
          "X   X",
          "     ",
          " XXX ",
          "X   X",
          "X   X",
          "X   X",
          "X   X",
          " XXX "
        ])
    },
    ?ö => %{
      encoding: ?ö,
      bitmap:
        defbitmap([
          " X X ",
          "     ",
          " XXX ",
          "X   X",
          "X   X",
          "X   X",
          " XXX "
        ])
    },
    ?Ü => %{
      encoding: ?Ü,
      bitmap:
        defbitmap([
          "X   X",
          "     ",
          "X   X",
          "X   X",
          "X   X",
          "X   X",
          "X   X",
          " XXX "
        ])
    },
    ?ü => %{
      encoding: ?ü,
      bitmap:
        defbitmap([
          " X X ",
          "     ",
          "X   X",
          "X   X",
          "X   X",
          "X   X",
          " XXX "
        ])
    },
    ?¨ => %{
      encoding: ?¨,
      name: "diaresis",
      bitmap:
        defbitmap([
          "X X",
          "   ",
          "   ",
          "   ",
          "   ",
          "   ",
          "   "
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
