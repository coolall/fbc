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

''
'' procedure and scope trees handling
''

option explicit
option escape

#include once "inc\fb.bi"
#include once "inc\fbint.bi"
#include once "inc\list.bi"
#include once "inc\ir.bi"
#include once "inc\rtl.bi"
#include once "inc\ast.bi"

declare function 	hNewProcNode	( byval proc as FBSYMBOL ptr ) as ASTNODE ptr

declare function 	hModLevelIsEmpty( byval p as ASTNODE ptr ) as integer

declare sub 		hModLevelAddRtInit( byval p as ASTNODE ptr )

declare sub 		hLoadProcResult ( byval proc as FBSYMBOL ptr )

declare function 	hDeclProcParams	( byval proc as FBSYMBOL ptr ) as integer

''::::
sub astProcListInit( )

	ast.proc.head = NULL
	ast.proc.tail = NULL
	ast.proc.curr = NULL
    ast.proc.oldsymtb = NULL

end sub

''::::
sub astProcListEnd( )

	ast.proc.head = NULL
	ast.proc.tail = NULL
	ast.proc.curr = NULL
	ast.proc.oldsymtb = NULL

end sub

'':::::
private function hNewProcNode( byval proc as FBSYMBOL ptr ) as ASTNODE ptr static
	dim as ASTNODE ptr n

	n = astNewNode( AST_NODECLASS_PROC, INVALID, NULL )

	n->sym = proc
	n->proc.head = NULL
	n->proc.tail = NULL

	'' add to list
	if( ast.proc.tail <> NULL ) then
		ast.proc.tail->next = n
	else
		ast.proc.head = n
	end if

	n->prev = ast.proc.tail
	n->next = NULL
	ast.proc.tail = n

	function = n

end function

'':::::
private sub hDelProcNode( byval n as ASTNODE ptr ) static

	n->proc.head = NULL
	n->proc.tail = NULL

	'' remove from list
	if( n->prev <> NULL ) then
		n->prev->next = n->next
	else
		ast.proc.head = n->next
	end If

	if( n->next <> NULL ) then
		n->next->prev = n->prev
	else
		ast.proc.tail = n->prev
	end If

	astDelNode( n )

end sub

''::::
private sub hProcFlush( byval p as ASTNODE ptr, _
						byval doemit as integer _
					  ) static

    dim as ASTNODE ptr n, nxt, prv
    dim as ASTNODE tmp
    dim as FBSYMBOL ptr sym

	''
	ast.proc.curr = p
	ast.doemit = doemit

	sym = p->sym

	env.scope = iif( p->proc.ismain, FB_MAINSCOPE, FB_MAINSCOPE+1 )
	env.currproc = sym
	symbSetLocalTb( @sym->proc.loctb )

	'' do pre-loading, before allocating variables on stack
	prv = @tmp
	n = p->proc.head
	do while( n <> NULL )
		nxt = n->next

		n = astOptimize( n )
		'' needed even when not optimizing
		n = astOptAssignment( n )
		n = astUpdStrConcat( n )

		prv->next = n
		prv = n
		n = nxt
	loop

	''
	symbProcAllocLocals( sym )

	symbProcAllocScopes( sym )

	'' add a call to fb_init if it's a static constructor
	'' (note: must be done here or ModLevelIsEmpty() will fail)
	if( doemit ) then
		if( symbIsConstructor( sym ) ) then
           	hModLevelAddRtInit( p )
		end if
	end if

	''
	if( ast.doemit ) then
		irEmitPROCBEGIN( sym, p->proc.initlabel )
	end if

	'' flush nodes
	n = p->proc.head
	do while( n <> NULL )
		nxt = n->next
		astLoad( n )
		astDelNode( n )
		n = nxt
	loop

    ''
    if( ast.doemit ) then
    	irEmitPROCEND( sym, p->proc.initlabel, p->proc.exitlabel )
    end if

    '' del symbols from hash and symbol tb's
    symbDelSymbolTb( @sym->proc.loctb, FALSE )

	''
	hDelProcNode( p )

	''
	ast.doemit = TRUE

end sub

''::::
private sub hProcFlushAll( ) static
    dim as ASTNODE ptr n
    dim as integer doemit
    dim as FBSYMBOL ptr sym

	'' procs should be sorted by include file

	do
        n = ast.proc.head
        if( n = NULL ) then
        	exit do
        end if

		sym = n->sym

		doemit = TRUE
		'' private?
		if( symbIsPrivate( sym ) ) then
			'' never called? skip
			if( symbGetIsCalled( sym ) = FALSE ) then
				doemit = FALSE

			'' module-level?
			elseif( symbIsModLevelProc( sym ) ) then
				doemit = (hModLevelIsEmpty( n ) = FALSE)
			end if
		end if

		hProcFlush( n, doemit )
	loop

end sub

''::::
sub astAdd( byval n as ASTNODE ptr ) static

	if( n = NULL ) then
		exit sub
	end if

	'' if node contains any type ini trees, they must be expanded first
	n = astTypeIniUpdate( n )

	''
	if( ast.proc.curr->proc.tail <> NULL ) then
		ast.proc.curr->proc.tail->next = n
	else
		ast.proc.curr->proc.head = n
	end if

	n->prev = ast.proc.curr->proc.tail
	n->next = NULL
	ast.proc.curr->proc.tail = n

end sub

''::::
sub astAddAfter( byval n as ASTNODE ptr, _
				 byval p as ASTNODE ptr _
			   ) static

	if( (p = NULL) or (n = NULL) ) then
		exit sub
	end if

	'' assuming no tree will type ini will be passed

	''
	if( p->next = NULL ) then
		ast.proc.curr->proc.tail = n
	end if

	n->prev = p
	n->next = p->next
	p->next = n

end sub

'':::::
function astProcBegin( byval sym as FBSYMBOL ptr, _
					   byval ismain as integer _
					 ) as ASTNODE ptr static

    dim as ASTNODE ptr n

	function = NULL

	'' alloc new node
	n = hNewProcNode( sym )
	if( n = NULL ) then
		exit function
	end if

	n->proc.ismain = ismain

	''
	sym->proc.loctb.head = NULL
	sym->proc.loctb.tail = NULL

	''
	if( sym->proc.ext = NULL ) then
		sym->proc.ext = callocate( len( FB_PROCEXT ) )
	end if

	''
	env.scope = iif( ismain, FB_MAINSCOPE, FB_MAINSCOPE+1 )
	env.currproc = sym
	ast.proc.oldsymtb = symbGetLocalTb( )
	symbSetLocalTb( @sym->proc.loctb )

	ast.proc.curr = n

	irProcBegin( sym )

    '' alloc parameters
    if( hDeclProcParams( sym ) = FALSE ) then
    	exit function
    end if

	'' alloc result local var
	if( symbGetType( sym ) <> FB_DATATYPE_VOID ) then
		if( symbAddProcResult( sym ) = NULL ) then
			exit function
		end if
	end if

	'' add init and exit labels
	n->proc.initlabel = symbAddLabel( NULL )
	n->proc.exitlabel = symbAddLabel( NULL )

	function = n

end function

'':::::
sub astProcEnd( byval n as ASTNODE ptr, _
			    byval callrtexit as integer ) static

    dim as FBSYMBOL ptr sym
    dim as integer issub

	sym = n->sym

	issub = (symbGetType( sym ) = FB_DATATYPE_VOID)

	'' del dyn arrays and all var-len strings (but the result if it returns a string)
	symbFreeLocalDynVars( sym, issub )

	'' if main(), END 0 must be called because it's not safe to return to crt if
	'' an ON ERROR module-level handler was called while inside some proc
	if( callrtexit ) then
		if( n->proc.ismain ) then
			rtlExitApp( NULL )
		end if
	end if

	'' if it's a function, load result
	if( issub = FALSE ) then
        hLoadProcResult( sym )
	end if

	''
	irProcEnd( sym )

	if( n->proc.ismain = FALSE ) then
		'' not private or inline? flush it..
		if( symbIsPrivate( sym ) = FALSE ) then
			hProcFlush( n, TRUE )

		'' remove from hash tb only
		else
			symbDelSymbolTb( @sym->proc.loctb, TRUE )
		end if

	'' main? flush all remaining, it's the latest
	else
		hProcFlushAll( )

	end if

	'' back to main
    env.scope = FB_MAINSCOPE
    env.currproc = env.main.proc
	symbSetLocalTb( ast.proc.oldsymtb )

	ast.proc.curr = ast.proc.head

end sub

'':::::
private function hDeclProcParams( byval proc as FBSYMBOL ptr ) as integer static
    dim as integer i
    dim as FBSYMBOL ptr p

	function = FALSE

	'' proc returns an UDT?
	if( symbGetType( proc ) = FB_DATATYPE_USERDEF ) then
		'' create an hidden arg if needed
		symbAddProcResultParam( proc )
	end if

	''
	i = 1
	p = symbGetProcHeadParam( proc )
	do while( p <> NULL )

		if( p->param.mode <> FB_PARAMMODE_VARARG ) then
			if( symbAddParam( symbGetName( p ), p ) = NULL ) then
				hReportParamError( proc, i, NULL, FB_ERRMSG_DUPDEFINITION )
				exit function
			end if
		end if

		p = symbGetParamNext( p )
		i += 1
	loop

	function = TRUE

end function

'':::::
private sub hLoadProcResult ( byval proc as FBSYMBOL ptr ) static
    dim as FBSYMBOL ptr s
    dim as ASTNODE ptr n, t
    dim as integer dtype

	s = symbLookupProcResult( proc )
	dtype = symbGetType( proc )
    n = NULL

	select case dtype

	'' if result is a string, a temp descriptor is needed, as the current one (on stack)
	'' will be trashed when the function returns (also, the string returned will be
	'' set as temp, so any assignment or when passed as parameter to another proc
	'' will deallocate this string)
	case FB_DATATYPE_STRING
		t = astNewVAR( s, 0, FB_DATATYPE_STRING )
		n = rtlStrAllocTmpResult( t )

	'' UDT? use the real type
	case FB_DATATYPE_USERDEF
		dtype = symbGetProcRealType( proc )
	end select

	if( n = NULL ) then
		n = astNewLOAD( astNewVAR( s, 0, dtype, NULL ), dtype, TRUE )
	end if

	astAdd( n )

end sub

''::::
private function hModLevelIsEmpty( byval p as ASTNODE ptr ) as integer
    dim as ASTNODE ptr n, nxt

	'' an empty module-level proc will have just the
	'' initial and final labels as nodes and nothing else
	'' (note: when debugging it will be emmited even if empty)

	n = p->proc.head
	if( n = NULL ) then
		return TRUE
	end if
	if( n->class <> AST_NODECLASS_LABEL ) then
		return FALSE
	end if

	n = n->next
	if( n = NULL ) then
		return TRUE
	end if
	if( n->class <> AST_NODECLASS_LABEL ) then
		return FALSE
	end if

	n = n->next
	if( n = NULL ) then
		return TRUE
	end if

	return FALSE

end function

''::::
private sub hModLevelAddRtInit( byval p as ASTNODE ptr )
    dim as ASTNODE ptr n

    n = p->proc.head
    if( n = NULL ) then
    	exit sub
    end if

	'' fb rt must be initialized before any static constructor
	'' is called but in any platform (but Windows) the .ctors
	'' list will be processed before main() is called by crt

	astAddAfter( rtlInitRt( ), n )

end sub


