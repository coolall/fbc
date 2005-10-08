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


'' quirk console statements (VIEW, LOCATE) parsing
''
'' chng: sep/2004 written [v1ctor]

option explicit
option escape

#include once "inc\fb.bi"
#include once "inc\fbint.bi"
#include once "inc\parser.bi"
#include once "inc\rtl.bi"
#include once "inc\ast.bi"

'':::::
'' ViewStmt	  =   VIEW (PRINT (Expression TO Expression)?) .
''
function cViewStmt(byval is_func as integer = FALSE, _
                   byref funcexpr as ASTNODE ptr = NULL ) as integer
    dim as ASTNODE ptr expr1, expr2
    dim as integer default_view, default_view_value

	function = FALSE

	default_view = is_func
    default_view_value = iif(is_func,-1,0)

	'' VIEW
	if( lexGetToken <> FB_TK_VIEW ) then
		exit function
	end if

	'' PRINT
	if( lexGetLookAhead(1) <> FB_TK_PRINT ) then
		exit function
	end if

	lexSkipToken( )
	lexSkipToken( )

	'' (Expression TO Expression)?
	if( not is_func ) then
    	if( cExpression( expr1 ) ) then
            if( not hMatch( FB_TK_TO ) ) then
                hReportError FB_ERRMSG_SYNTAXERROR
                exit function
            end if

            hMatchExpression( expr2 )
        else
            default_view = TRUE
        end if
	end if

    if( default_view ) then
        if( is_func ) then
            hMatchLPRNT()
            hMatchRPRNT()
        end if
        expr1 = astNewCONSTi( default_view_value, IR_DATATYPE_INTEGER )
        expr2 = astNewCONSTi( default_view_value, IR_DATATYPE_INTEGER )
	end if

	funcexpr = rtlConsoleView( expr1, expr2 )
    function = funcexpr <> NULL

    if( not is_func ) then
    	astAdd( funcexpr )
    end if

end function

'':::::
function cWidthStmt( byval isfunc as integer ) as ASTNODE ptr
	dim as ASTNODE ptr fnum, width_arg, height_arg, dev_name
    dim as ASTNODE ptr func
    dim as integer checkrprnt

	function = NULL

	lexSkipToken( )

	if( isfunc ) then
		'' '('?
		checkrprnt = hMatch( CHAR_LPRNT )
	else
		checkrprnt = FALSE
	end if

    if( isfunc ) then
    	' Width Screen?
    	if( (not checkrprnt) or _                   '' !!!FIXME!!! change to OrElse
    		hMatch( CHAR_RPRNT ) ) then
    		return rtlWidthScreen( NULL, NULL, isfunc )
    	end if

	end if

    if( hMatch( FB_TK_LPRINT ) ) then
       ' fb_WidthDev
       dev_name = astNewCONSTs( "LPT1:" )
       hMatchExpression( width_arg )

       function = rtlWidthDev( dev_name, width_arg, isfunc )

	elseif( hMatch( CHAR_SHARP ) ) then
    	' fb_WidthFile

        hMatchExpression( fnum )

        if( hMatch( CHAR_COMMA ) ) then
        	hMatchExpression( width_arg )
		else
        	width_arg = astNewCONSTi( -1, IR_DATATYPE_INTEGER )
		end if

        function = rtlWidthFile( fnum, width_arg, isfunc )

	elseif( hMatch( CHAR_COMMA ) ) then
    	' fb_WidthScreen
        width_arg = astNewCONSTi( -1, IR_DATATYPE_INTEGER )
        hMatchExpression( height_arg )
        function = rtlWidthScreen( width_arg, height_arg, isfunc )

	else
		hMatchExpression( dev_name )
        select case astGetDataType( dev_name )
        case IR_DATATYPE_STRING, IR_DATATYPE_FIXSTR:
            ' fb_WidthDev

        	if( hMatch( CHAR_COMMA ) ) then
            	hMatchExpression( width_arg )
			else
            	width_arg = astNewCONSTi( -1, IR_DATATYPE_INTEGER )
			end if
            function = rtlWidthDev( dev_name, width_arg, isfunc )

		case else
        	' fb_WidthScreen
            width_arg = dev_name
            dev_name = NULL

            if( hMatch( CHAR_COMMA ) ) then
            	hMatchExpression( height_arg )
			else
            	height_arg = astNewCONSTi( -1, IR_DATATYPE_INTEGER )
			end if
            function = rtlWidthScreen( width_arg, height_arg, isfunc )

		end select
	end if

	if( checkrprnt ) then
		'' ')'
		hMatchRPRNT( )
	end if

end function

'':::::
function cLocateStmt( byval isfunc as integer ) as ASTNODE ptr
	dim as ASTNODE ptr row_arg, col_arg, cursor_vis_arg
    dim as ASTNODE ptr func

	function = NULL

	'' LOCATE
	lexSkipToken( )

	if( isfunc ) then
		'' '('?
		hMatchLPRNT()
	end if

    cExpression( row_arg )
    if( hMatch( CHAR_COMMA ) ) then
    	cExpression( col_arg )
	    if( hMatch( CHAR_COMMA ) ) then
		    cExpression( cursor_vis_arg )
	    end if
    end if

	if( isfunc ) then
		'' ')'?
		hMatchRPRNT()
	end if

    function = rtlLocate( row_arg, col_arg, cursor_vis_arg, isfunc )

end function

'':::::
'' ScreenFunct   =   SCREEN '(' expr ',' expr ( ',' expr )? ')'
''
function cScreenFunct( byref funcexpr as ASTNODE ptr ) as integer
    dim as ASTNODE ptr yexpr, xexpr, fexpr

	function = FALSE

	'' SCREEN
	lexSkipToken( )

	hMatchLPRNT( )

	hMatchExpression( yexpr )

	hMatchCOMMA( )

	hMatchExpression( xexpr )

	fexpr = NULL
	if( hMatch( CHAR_COMMA ) ) then
		hMatchExpression( fexpr )
	end if

	hMatchRPRNT( )

	funcexpr = rtlConsoleReadXY( yexpr, xexpr, fexpr )

	function = funcexpr <> NULL

end function

