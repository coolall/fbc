''	FreeBASIC - 32-bit BASIC Compiler.
''	Copyright (C) 2004-2005 Andre Victor T. Vicentini (av1ctor@yahoo.com.br)
''
''	This program is free software; you can redistribute it and/or modify
''	it under the terms of the GNU General Public License as published by
''	the Free Software Foundation; either version 2 of the License, or
''	(at your option) any later version.
''
''	This program is distributed in the hope that it will be useful,
''	but WITHOUT ANY WARRANTY; without even the implied warranty of
''	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
''	GNU General Public License for more details.
''
''	You should have received a copy of the GNU General Public License
''	along with this program; if not, write to the Free Software
''	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA.

'' AST type initializer nodes
'' tree	    : l = head; r = (when constructing: tail, when updating: base var)
'' expr node: l = expr; r = next
'' pad node : l = NULL; r = next
''
'' chng: mar/2006 written [v1ctor]

option explicit
option escape

#include once "inc\fb.bi"
#include once "inc\fbint.bi"
#include once "inc\ir.bi"
#include once "inc\ast.bi"

'':::::
function astTypeIniBegin( byval dtype as integer, _
						  byval subtype as FBSYMBOL ptr _
					  	) as ASTNODE ptr static

    dim as ASTNODE ptr n

	'' alloc new node
	n = astNewNode( AST_NODECLASS_TYPEINI, dtype, subtype )
	function = n

	if( n = NULL ) then
		exit function
	end if

	n->typeini.ofs = 0

end function

'':::::
sub astTypeIniEnd( byval tree as ASTNODE ptr, _
				   byval isinitializer as integer _
				 ) static

    dim as ASTNODE ptr n, p, l, r

	'' can't leave r pointing to the any node as the
	'' tail node is linked already
	tree->r = NULL

	if( isinitializer = FALSE ) then
		ast.typeinicnt += 1
	end if

	'' merge nested type ini trees
    p = NULL
    n = tree->l
    do while( n <> NULL )
    	'' expression node?
    	if( n->class <> AST_NODECLASS_TYPEINI_PAD ) then
			l = n->l
			'' is it an ini tree too?
			if( l->class = AST_NODECLASS_TYPEINI ) then
				ast.typeinicnt -= 1

    			r = n->r
    			astDelNode( n )
    			n = l->l
    			astDelNode( l )

    			'' relink
    			if( p <> NULL ) then
    				p->r = n
    			else
    				tree->l = n
    			end if

    			do while( n->r <> NULL )
    				n = n->r
    			loop

    			n->r = r
			end if
		end if

		'' next
		p = n
		n = n->r
	loop

end sub

'':::::
private function hAddNode( byval tree as ASTNODE ptr, _
						   byval class_ as AST_NODECLASS, _
						   byval dtype as FB_DATATYPE, _
						   byval subtype as FBSYMBOL ptr _
					   	 ) as ASTNODE ptr static

	dim as ASTNODE ptr n

	n = astNewNode( class_, dtype, subtype )

	if( tree->r <> NULL ) then
		tree->r->r = n
	else
		tree->l = n
	end if

    tree->r = n

    function = n

end function

'':::::
function astTypeIniAddPad( byval tree as ASTNODE ptr, _
						   byval bytes as integer _
					   	 ) as ASTNODE ptr static

	dim as ASTNODE ptr n

	n = hAddNode( tree, AST_NODECLASS_TYPEINI_PAD, INVALID, NULL )

	n->typeini.bytes = bytes

	function = n

end function

'':::::
function astTypeIniAddExpr( byval tree as ASTNODE ptr, _
						 	byval expr as ASTNODE ptr, _
						 	byval sym as FBSYMBOL ptr, _
						 	byval ofs as integer _
					   	  ) as ASTNODE ptr static

	dim as ASTNODE ptr n

	n = hAddNode( tree, AST_NODECLASS_TYPEINI_EXPR, expr->dtype, expr->subtype )

	n->l = expr
	n->sym = sym
	n->typeini.ofs = ofs

	function = n

end function

'':::::
private function hFlushTree( byval tree as ASTNODE ptr, _
					   	     byval basesym as FBSYMBOL ptr _
					 	   ) as integer

    dim as ASTNODE ptr n, nxt
    static as ASTNODE ptr lside
    static as FBSYMBOL ptr sym

	function = FALSE

    n = tree->l
    do while( n <> NULL )
        nxt = n->r

    	if( n->class <> AST_NODECLASS_TYPEINI_PAD ) then
        	sym = n->sym

        	lside = astNewVAR( basesym, _
        					   n->typeini.ofs, _
        					   symbGetType( sym ), _
        					   symbGetSubtype( sym ) )

        	'' field?
        	if( symbIsUDTElm( sym ) ) then
        		lside = astNewFIELD( lside, _
        							 sym, _
        							 symbGetType( sym ), _
        							 symbGetSubtype( sym ) )
        	end if

			astAdd( astNewASSIGN( lside, n->l, FALSE ) )

    	else
    		astDelNode( n )
    	end if

    	n = nxt
    loop

	function = TRUE

end function

'':::::
private function hFlushExprStatic( byval n as ASTNODE ptr, _
					   	   		   byval basesym as FBSYMBOL ptr _
					 	 		 ) as integer static

	dim as ASTNODE ptr expr
	dim as integer edtype, sdtype
	dim as FBSYMBOL ptr sym, litsym

	function = FALSE

	expr = n->l
	sym = n->sym
	edtype = astGetDataType( expr )
	sdtype = symbGetType( sym )

	litsym = NULL
	select case edtype
	case FB_DATATYPE_CHAR, FB_DATATYPE_WCHAR
		litsym = astGetStrLitSymbol( expr )
	end select

	'' not a literal string?
	if( litsym = NULL ) then

    	'' offset?
		if( astIsOFFSET( expr ) ) then
			irEmitVARINIOFS( astGetSymbol( expr ) )

		'' anything else
		else
			'' different types?
			if( edtype <> sdtype ) then
				expr = astNewCONV( INVALID, _
								   sdtype, _
								   symbGetSubtype( sym ), _
								   expr )
                '' shouldn't happen, but..
				if( expr = NULL ) then
			   		hReportError( FB_ERRMSG_INVALIDDATATYPES, TRUE )
					exit function
				end if
			end if

			select case as const sdtype
			case FB_DATATYPE_LONGINT, FB_DATATYPE_ULONGINT
				irEmitVARINI64( sdtype, astGetValLong( expr ) )
			case FB_DATATYPE_SINGLE, FB_DATATYPE_DOUBLE
				irEmitVARINIf( sdtype, astGetValFloat( expr ) )
			case else
				irEmitVARINIi( sdtype, astGetValInt( expr ) )
			end select
		end if

	'' literal string..
	else
		'' not a wstring?
		if( sdtype <> FB_DATATYPE_WCHAR ) then

			'' convert?
			if( edtype <> FB_DATATYPE_WCHAR ) then
				'' less the null-char
				irEmitVARINISTR( symbGetStrLen( sym ) - 1, _
						 	 	 symbGetVarLitText( litsym ), _
						 	 	 symbGetStrLen( litsym ) - 1 )
			else
				'' ditto
				irEmitVARINISTR( symbGetStrLen( sym ) - 1, _
						 	 	 str( *symbGetVarLitTextW( litsym ) ), _
						 	 	 symbGetWstrLen( litsym ) - 1 )
			end if


		'' wstring..
		else

			'' convert?
			if( edtype <> FB_DATATYPE_WCHAR ) then
				'' less the null-char
				irEmitVARINIWSTR( symbGetWstrLen( sym ) - 1, _
						 	  	  wstr( *symbGetVarLitText( litsym ) ), _
						 	  	  symbGetStrLen( litsym ) - 1 )
			else
				'' ditto
				irEmitVARINIWSTR( symbGetWstrLen( sym ) - 1, _
						 	  	  symbGetVarLitTextW( litsym ), _
						 	  	  symbGetWstrLen( litsym ) - 1 )
			end if

		end if

	end if

	astDelTree( n->l )
	n->l = NULL

	function = TRUE

end function

'':::::
private function hFlushTreeStatic( byval tree as ASTNODE ptr, _
					   	   		   byval basesym as FBSYMBOL ptr _
					 	 		 ) as integer static

    dim as ASTNODE ptr n, nxt

	function = FALSE

	irEmitVARINIBEGIN( basesym )

    n = tree->l
    do while( n <> NULL )
        nxt = n->r

    	if( n->class = AST_NODECLASS_TYPEINI_PAD ) then
    		irEmitVARINIPAD( n->typeini.bytes )
    	else
			hFlushExprStatic( n, basesym )
    	end if

        astDelNode( n )
    	n = nxt
    loop

	irEmitVARINIEND( basesym )

	function = TRUE

end function

'':::::
function astTypeIniFlush( byval tree as ASTNODE ptr, _
						  byval basesym as FBSYMBOL ptr, _
						  byval isstatic as integer, _
						  byval isinitializer as integer _
						) as integer static

	if( isinitializer = FALSE ) then
		ast.typeinicnt -= 1
	end if

	if( isstatic ) then
		function = hFlushTreeStatic( tree, basesym )
	else
		function = hFlushTree( tree, basesym )
	end if

	astDelNode( tree )

end function

'':::::
private function hExprIsConst( byval n as ASTNODE ptr ) as integer static
    dim as FBSYMBOL ptr sym, litsym
    dim as ASTNODE ptr expr
    dim as integer sdtype, edtype

    sym = n->sym
    expr = n->l

    sdtype = symbGetType( sym )
    edtype = astGetDataType( expr )

	'' check if it's a literal string
	litsym = NULL
	select case edtype
	case FB_DATATYPE_CHAR, FB_DATATYPE_WCHAR
		litsym = astGetStrLitSymbol( expr )
	end select

	'' not a literal string?
	if( litsym = NULL ) then

		'' string?
		if( hIsString( sdtype ) ) then
			if( hIsString( edtype ) ) then
				hReportError( FB_ERRMSG_EXPECTEDCONST, TRUE )
			else
				hReportError( FB_ERRMSG_INVALIDDATATYPES, TRUE )
			end if
			exit function

		elseif( hIsString( edtype ) ) then
		    hReportError( FB_ERRMSG_INVALIDDATATYPES, TRUE )
			exit function
		end if

		'' bit field?
		if( symbIsUDTElm( sym ) ) then
		    if( symbGetType( sym ) = FB_DATATYPE_BITFIELD ) then
		    	hReportError( FB_ERRMSG_INVALIDDATATYPES, TRUE )
				exit function
			end if
		end if

		'' offset?
		if( astIsOFFSET( expr ) ) then

			'' different types?
			if( (symbGetDataClass( sdtype ) <> FB_DATACLASS_INTEGER) or _
				(symbGetDataSize( sdtype ) <> FB_POINTERSIZE) ) then
				hReportError( FB_ERRMSG_INVALIDDATATYPES, TRUE )
				exit function
			end if

		else
			'' not a constant?
			if( astIsCONST( expr ) = FALSE ) then
				hReportError( FB_ERRMSG_EXPECTEDCONST, TRUE )
				exit function
			end if

		end if

	'' literal string..
	else
		'' not a string?
		if( hIsString( sdtype ) = FALSE ) then
			hReportError( FB_ERRMSG_INVALIDDATATYPES, TRUE )
			exit function
		end if

		'' can't be a variable-len string
		if( sdtype = FB_DATATYPE_STRING ) then
			hReportError( FB_ERRMSG_CANTINITDYNAMICSTRINGS, TRUE )
			exit function
		end if

	end if

	function = TRUE

end function

'':::::
function astTypeIniIsConst( byval tree as ASTNODE ptr ) as integer static
    dim as ASTNODE ptr n

	function = FALSE

    n = tree->l
    do while( n <> NULL )

    	if( n->class <> AST_NODECLASS_TYPEINI_PAD ) then
			if( hExprIsConst( n ) = FALSE ) then
				exit function
			end if
    	end if

    	n = n->r
    loop

	function = TRUE

end function

'':::::
private sub hWalk( byval node as ASTNODE ptr, _
				   byval parent as ASTNODE ptr )

    dim as ASTNODE ptr expr
    dim as FBSYMBOL ptr sym

	if( node->class = AST_NODECLASS_TYPEINI ) then
		sym = symbAddTempVar( node->dtype, node->subtype, FALSE, FALSE )

		expr = astNewVAR( sym, 0, node->dtype, node->subtype )
		if( parent->l = node ) then
			parent->l = expr
		else
			parent->r = expr
		end if

		astTypeIniFlush( node, sym, FALSE, FALSE )

    	exit sub
    end if

	'' walk
	expr = node->l
	if( expr <> NULL ) then
		hWalk( expr, node )
	end if

	expr = node->r
	if( expr <> NULL ) then
		hWalk( expr, node )
	end if

end sub

'':::::
function astTypeIniUpdate( byval tree as ASTNODE ptr ) as ASTNODE ptr
    dim as ASTNODE ptr expr

	function = tree

    if( ast.typeinicnt <= 0 ) then
    	exit function
    end if

	'' walk
	expr = tree->l
	if( expr <> NULL ) then
		hWalk( expr, tree )
	end if

	expr = tree->r
	if( expr <> NULL ) then
		hWalk( expr, tree )
	end if

end function

'':::::
sub astTypeIniUpdCnt( byval tree as ASTNODE ptr )

	if( tree->class = AST_NODECLASS_TYPEINI ) then
		ast.typeinicnt += 1
	end if

	'' walk
	if( tree->l <> NULL ) then
		astTypeIniUpdCnt( tree->l )
	end if

	if( tree->r <> NULL ) then
		astTypeIniUpdCnt( tree->r )
	end if

end sub

'':::::
function astTypeIniGetHead( byval tree as ASTNODE ptr ) as ASTNODE ptr

	'' head node will be always an EXPR
	function = tree->l->l

end function
