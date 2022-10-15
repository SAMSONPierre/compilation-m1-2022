%{ (* -*- tuareg -*- *)

  open HopixAST
  open Position

%}

%token EOF TYPE LESS GREATER EQUAL COMMA EXTERN 
COLON BAR LPAREN RPAREN LET FUN AND MATCH IF THEN ELSE REF WHILE DO UNTIL FOR FROM TO LCBRACKET RCBRACKET 
LSBRACKET RSBRACKET DOT BACKSLASH EXCLAMATION SEMICOLON ARROW STAR UNDERSCORE AMPERSAND ASSIGN

%token <string> ID TYPE_VARIABLE CONSTR_ID STRING CHAR BINOP
%token <Mint.t> INT

%left BAR
%left COMMA
%left AMPERSAND
%left STAR
%left DOT
%left REF
%left ASSIGN
%left EXCLAMATION
%nonassoc ARROW
%right SEMICOLON
%left BINOP

%start<HopixAST.t> program

%%

program:
  | p=located(definition)* EOF                 {p}
  | error 
  {
    let pos = Position.lex_join $startpos $endpos in
    Error.error "parsing" pos "Syntax error."
  }

definition:
  | TYPE tc=located(tcon) df=definition_variables dt=definition_tdefinition  {DefineType(tc,df,dt)}
  | EXTERN vi=located(varid) COLON ts=located(type_scheme)   {DeclareExtern(vi,ts)}
  | v=vdefinition                                                             {DefineValue(v)}

vdefinition:
  | LET vi=located(varid) ts=preceded(COLON, located(type_scheme))? EQUAL e=located(expr)  {SimpleValue(vi,ts,e)}
  | FUN f=separated_nonempty_list(AND, fundef)                                  {RecFunctions(f)}

fundef: ts=preceded(COLON, located(type_scheme))? vi=located(varid) p=located(pattern) EQUAL e=located(expr)   {(vi,ts,FunctionDefinition(p,e))}

varid: i=ID {Id(i)}

tcon: i=ID {TCon(i)}

definition_variables:
  | tvl=loption(delimited(LESS, separated_list(COMMA, located(tid)), GREATER))  {tvl}

tid: i=TYPE_VARIABLE      {TId(i)}

definition_tdefinition:
  |                       {Abstract}
  | EQUAL t=tdefinition   {t}

tdefinition: 
  | ci=located(cid) ct=tdefinition_types ctl=tdefinition_constr*      {DefineSumType((ci,ct)::ctl)}
  | ctl=tdefinition_constr+                                           {DefineSumType(ctl)}
  | tll=delimited(LCBRACKET, separated_list(COMMA, tdefinition_label), RCBRACKET)  {DefineRecordType(tll)}

cid: i=CONSTR_ID {KId(i)}

tdefinition_constr: 
  | BAR ci=located(cid) ct=tdefinition_types       {(ci,ct)}

tdefinition_types:
  | tl=loption(delimited(LPAREN, separated_nonempty_list(COMMA,located(ty)), RPAREN))   {tl}


tdefinition_label: id=located(id) COLON t=located(ty)           {(id, t)}

id: i=ID {LId(i)}

ty:
  | tc=tcon ty=loption(delimited(LESS, separated_nonempty_list(COMMA, located(ty)), GREATER)) {TyCon(tc, ty)}
  | t1=located(ty) ARROW t2=located(ty) {TyArrow(t1,t2)}
  | t1=located(ty) STAR t2=located(ty) {TyTuple(t1::[t2])}
  | t=tid {TyVar(t)}
  | t=delimited(LPAREN, ty, RPAREN) {t}

expr:
  | l=located(literal)  {Literal(l)}
  | vid=located(varid) tyl=tyList {Variable(vid,tyl)}
  | cid=located(cid) tyl=tyList expl=loption(delimited(LPAREN, separated_nonempty_list(COMMA,located(expr)), RPAREN)) {Tagged(cid,tyl,expl)}
  | tupl=delimited(LPAREN, expr_tuple, RPAREN) {Tuple(tupl)}
  | LPAREN e=located(expr) RPAREN {Tuple([e])}
  // warning shift reduce
  | LCBRACKET idp=separated_nonempty_list(COMMA, separated_pair(located(id), EQUAL, located(expr))) RCBRACKET ty=delimited(LESS, separated_list(COMMA, located(ty)), GREATER)? {Record(idp,ty)}
  | exp1 = located(expr) DOT lid = located(id) {Field(exp1,lid)}
  | exp1 = located(expr) SEMICOLON exp2 = located(expr) {Sequence(exp1::[exp2])}
  //warning shift reduce avec definition
  | vdef = vdefinition SEMICOLON exp = located(expr) {Define(vdef,exp)}
  | BACKSLASH p = located(pattern) ARROW exp = located(expr) {Fun(FunctionDefinition(p,exp))}
  //cyclic
  | exp1 = located(expr) exp2 = located(expr) {Apply(exp1,exp2)}
  // A VOIR
  | exp1 = located(expr) b=BINOP exp2 = located(expr) {
    let op = "`" ^ b ^ "`" in
    let binop = Position.with_poss $startpos $endpos(Id(op)) in
    let id = Position.with_poss $startpos $endpos(Variable(binop,None)) in 
    let apply = Position.with_poss $startpos $endpos(Apply(id, exp1)) in
    Apply(apply,  exp2)
  }
  | MATCH LPAREN exp1 = located(expr) RPAREN LCBRACKET br = branches RCBRACKET {Case(exp1,br)}
  | IF LPAREN exp1 = located(expr) RPAREN THEN LCBRACKET exp2 = located(expr) RCBRACKET exp3 = located(els) {IfThenElse(exp1,exp2,exp3)}
  | REF exp = located(expr) {Ref(exp)}
  | exp1 = located(expr) ASSIGN exp2 = located(expr) {Assign(exp1,exp2)}
  | EXCLAMATION exp = located(expr) {Read(exp)}
  | WHILE LPAREN exp1 = located(expr) RPAREN LCBRACKET exp2 = located(expr) RCBRACKET {While(exp1,exp2)}
  | DO LCBRACKET exp1 = located(expr) RCBRACKET UNTIL LPAREN exp2 = located(expr) RPAREN {While(exp2,exp1)}
  | FOR vid = located(varid) FROM LPAREN exp1 = located(expr) RPAREN TO LPAREN exp2 = located(expr) RPAREN LCBRACKET exp3 = located(expr) RCBRACKET {For(vid,exp1,exp2,exp3)}
  | LPAREN exp = located(expr) COLON ty = located(ty) RPAREN {TypeAnnotation(exp,ty)}


expr_tuple: exp1=located(expr) COMMA exp2=located(expr) {exp1::[exp2]}

els:
| {Tuple([])}
| ELSE LCBRACKET exp = expr RCBRACKET {exp}

branches:
  | b=  located(branch) {[b]}
  | bl = preceded(BAR,located(branch))* {bl}

branch:
  p= located(pattern) ARROW e= located(expr) {Branch(p,e)}


tyList:
  | l=delimited(LESS,separated_list(COMMA,located(ty)),GREATER)?  {l}

literal:
  | i=INT {LInt(i)}
  | s=STRING {LString(s)}
  | c=CHAR {LChar(c.[0])}

type_scheme:
  | tsv=loption(delimited(LSBRACKET, located(tid)+, RSBRACKET)) ty=located(ty)  {ForallTy(tsv,ty)}

pattern:
  | vi=located(varid)  {PVariable(vi)}
  | UNDERSCORE {PWildcard}
  | p=pattern_tuple {PTuple(p)}
  | p=located(pattern) COMMA t=located(ty) {PTypeAnnotation(p,t)}
  | l=located(literal) {PLiteral(l)}
  | pl=pattern_label ty=pattern_ty {PRecord(pl,ty)}
  | p1=located(pattern) BAR p2=located(pattern) {POr(p1::[p2])}
  | p1=located(pattern) AMPERSAND p2=located(pattern) {PAnd(p1::[p2])}

pattern_label: LCBRACKET idp=separated_nonempty_list(COMMA, separated_pair(located(id), EQUAL, located(pattern))) RCBRACKET {idp}

pattern_tuple: p=delimited(LPAREN, separated_nonempty_list(COMMA, located(pattern)), RPAREN) {p}

pattern_ty: ty=delimited(LESS, separated_nonempty_list(COMMA, located(ty)), GREATER)? {ty}

%inline located(X): x=X {
  Position.with_poss $startpos $endpos x
}