/*
 *  libfb - FreeBASIC's runtime library
 *	Copyright (C) 2004-2005 Andre Victor T. Vicentini (av1ctor@yahoo.com.br)
 *
 *  This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Lesser General Public
 *  License as published by the Free Software Foundation; either
 *  version 2.1 of the License, or (at your option) any later version.
 *
 *  This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Lesser General Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser General Public
 *  License along with this library; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

/*
 * str_ftoa.c -- float to string, internal usage
 *
 * chng: dec/2005 written [v1ctor]
 *
 */

#include <stdio.h>
#include "fb.h"


/*:::::*/
char *fb_hFloat2Str( double val, char *buffer, int precision, int addblank )
{
	int len;
	char *p;

	if( addblank == FB_TRUE )
		p = &buffer[1];
	else
		p = buffer;

#ifdef WIN32
	_gcvt( val, precision, p );

#else
	char fmtstr[16];

	sprintf( fmtstr, "%%.%dg", precision );

	sprintf( p, fmtstr, val );

#endif

	len = strlen( p );

	/* skip the dot at end if any */
	if( len > 0 )
		if( p[len-1] == '.' )
			p[len-1] = '\0';

	/* */
	if( addblank == FB_TRUE )
	{
		if( p[0] != '-' )
		{
			buffer[0] = ' ';
			return &buffer[0];
		}
		else
			return p;
	}
	else
		return p;
}

