defmodule Octopus.Font.BlinkenLightsRegular do
  require Octopus.Font
  alias Octopus.Font

  @characters %{
    0 => %{
      encoding: 0,
      name: "defaultchar",
      bitmap:
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
          " X",
          "X "
        ])
    },
    ?- => %{
      encoding: ?-,
      bitmap:
        Font.defbitmap([
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
        Font.defbitmap([
          "X"
        ])
    },
    ?/ => %{
      encoding: ?/,
      bitmap:
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
          "  XX  ",
          " XXXX ",
          "XX  XX",
          "      ",
          "      ",
          "      ",
          "      "
        ])
    },
    ?_ => %{
      encoding: ?_,
      bitmap:
        Font.defbitmap([
          "XXXXXX"
        ])
    },
    ?` => %{
      encoding: ?`,
      bitmap:
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
          "      ",
          "      ",
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
          "XX",
          "XX",
          "XX",
          "  ",
          "XX",
          "XX",
          "XX"
        ])
    },
    ?ß => %{
      encoding: ?ß,
      bb_y_off: -1,
      bitmap:
        Font.defbitmap([
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
        Font.defbitmap([
          "      ",
          "X    X",
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
          "X   X",
          " XXX ",
          "X   X",
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
          " X",
          "X "
        ])
    },
    ?µ => %{
      encoding: ?µ,
      name: "micro sign",
      bb_y_off: -1,
      bitmap:
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
        Font.defbitmap([
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
