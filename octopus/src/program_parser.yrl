Nonterminals term factor shift comp sum expr expr_ bitwise bool uminus uplus args.
Terminals float ident '||' '&&' '|' '&' '^' '+' '-' '*' '**' '/' '%' '!' '~' '<<' '>>' '<=' '>=' '<' '>' '==' '!=' '(' ')' ','.
Rootsymbol expr.
Endsymbol '$end'.

Left 100 '||'.
Left 200 '&&'.
Left 300 '|'.
Left 400 '^'.
Left 500 '&'.
Nonassoc 600 '==' '!='.
Left 700 '<' '>' '<=' '>='.
Left 800 '<<' '>>'.
Left 1000 '*' '/' '%'.
Left 1100 '+' '-'.
Right 1200 '**'.
Unary 1300 '!' '~'.
Unary 1400 uminus uplus.

expr -> expr_ : '$1'.

expr_ -> bool : '$1'.

bool -> bitwise '||' bool : {logical_or, ['$1', '$3']}.
bool -> bitwise '&&' bool : {logical_and, ['$1', '$3']}.
bool -> bitwise : '$1'.

bitwise -> comp '&' bitwise : {bitwise_and, ['$1', '$3']}.
bitwise -> comp '^' bitwise : {bitwise_xor, ['$1', '$3']}.
bitwise -> comp '\|' bitwise : {bitwise_or, ['$1', '$3']}.
bitwise -> comp : '$1'.

comp -> shift '<=' comp : {lte, ['$1', '$3']}.
comp -> shift '>=' comp : {gte, ['$1', '$3']}.
comp -> shift '<' comp : {lt, ['$1', '$3']}.
comp -> shift '>' comp : {gt, ['$1', '$3']}.
comp -> shift '==' comp : {eq, ['$1', '$3']}.
comp -> shift '!=' comp : {neq, ['$1', '$3']}.
comp -> shift : '$1'.

shift -> sum '<<' shift : {shift_left, ['$1', '$3']}.
shift -> sum '>>' shift : {shift_right, ['$1', '$3']}.
shift -> sum : '$1'.

sum -> term '+' sum : {add, ['$1', '$3']}.
sum -> term '-' sum : {sub, ['$1', '$3']}.
sum -> term : '$1'.

term -> factor '**' term : {pow, ['$1', '$3']}.
term -> factor '*' term : {mul, ['$1', '$3']}.
term -> factor '/' term : {divi, ['$1', '$3']}.
term -> factor '%' term : {mod, ['$1', '$3']}.
term -> factor : '$1'.

args -> expr_ : ['$1'].
args -> expr_ ',' args : ['$1' | '$3'].

factor -> uminus : '$1'.
factor -> uplus : '$1'.
factor -> '(' expr_ ')' : '$2'.
factor -> '!' expr_ : {logical_not, ['$2']}.
factor -> '~' expr_ : {bitwise_not, ['$2']}.
factor -> ident '(' ')' : {call, [element(2, '$1')]}.
factor -> ident '(' args  ')' : {call, [element(2, '$1') | '$3']}.
factor -> float : element(2, '$1').
factor -> ident : element(2, '$1').

uminus -> '-' factor : {unary_minus, ['$2']}.
uplus -> '+' factor : {unary_plus, ['$2']}.
