Definitions.

Digit = [0-9]
NonZeroDigit = [1-9]
Sign = [-+]
FractionalPart = Digit+

Rules.

%% ident
[a-zA-Z_][a-zA-Z0-9_]* : {token, {ident, TokenChars}}.

%% float
[0-9]+\.[0-9]+ : {token, {float, list_to_float(TokenChars)}}.
[0-9]+ : {token, {float, list_to_integer(TokenChars) * 1.0}}.

\( : {token, {'(', TokenLine}}.
\) : {token, {')', TokenLine}}.
, : {token, {',', TokenLine}}.

! : {token, {'!', TokenLine}}.
~ : {token, {'~', TokenLine}}.

\*\* : {token, {'**', TokenLine}}.
\* : {token, {'*', TokenLine}}.
/ : {token, {'/', TokenLine}}.
\% : {token, {'%', TokenLine}}.

\+ : {token, {'+', TokenLine}}.
\- : {token, {'-', TokenLine}}.

<< : {token, {'<<', TokenLine}}.
>> : {token, {'>>', TokenLine}}.

<= : {token, {'<=', TokenLine}}.
>= : {token, {'>=', TokenLine}}.
< : {token, {'<', TokenLine}}.
> : {token, {'>', TokenLine}}.
== : {token, {'==', TokenLine}}.
!= : {token, {'!=', TokenLine}}.

\|\| : {token, {'||', TokenLine}}.
\| : {token, {'|', TokenLine}}.
& : {token, {'&', TokenLine}}.
&& : {token, {'&&', TokenLine}}.
\^ : {token, {'^', TokenLine}}.

[\s\n\r\t]+ : skip_token.
[\000] : {end_token, {'$end', TokenLine}}.


Erlang code.
