%top {
/* Include this before everything else, for various large-file definitions */
#include "config.h"
#include <wireshark.h>
}

/*
 * We want a reentrant scanner.
 */
%option reentrant

/*
 * We don't read interactively from the terminal.
 */
%option never-interactive

/*
 * We want to stop processing when we get to the end of the input.
 */
%option noyywrap

/*
 * The type for the state we keep for the scanner (and parser).
 */
%option extra-type="ascend_state_t *"

/*
 * Prefix scanner routines with "ascend_" rather than "yy", so this scanner
 * can coexist with other scanners.
 */
%option prefix="ascend_"

/*
 * We have to override the memory allocators so that we don't get
 * "unused argument" warnings from the yyscanner argument (which
 * we don't use, as we have a global memory allocator).
 *
 * We provide, as macros, our own versions of the routines generated by Flex,
 * which just call malloc()/realloc()/free() (as the Flex versions do),
 * discarding the extra argument.
 */
%option noyyalloc
%option noyyrealloc
%option noyyfree

%{
/* ascend_scanner.l
 *
 * Wiretap Library
 * Copyright (c) 1998 by Gilbert Ramirez <gram@alumni.rice.edu>
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#include <stdlib.h>
#include <string.h>

#include "wtap-int.h"
#include "ascendtext.h"
#include "ascend-int.h"
#include "ascend_parser.h"
#include "file_wrappers.h"

/*
 * Disable diagnostics in the code generated by Flex.
 */
DIAG_OFF_FLEX

static int ascend_yyinput(void *buf, ascend_state_t *parser_state) {
    int c = file_getc(parser_state->fh);
    if (c == EOF) {
        parser_state->err = file_error(parser_state->fh,
            &parser_state->err_info);
        if (parser_state->err == 0)
        parser_state->err = WTAP_ERR_SHORT_READ;
        return YY_NULL;
    } else {
        *(char *) buf = c;
        return 1;
    }
}

#define YY_INPUT(buf, result, max_size) \
  do { (result) = ascend_yyinput((buf), yyextra); } while (0)


/* Count bytes read. This is required in order to rewind the file
 * to the beginning of the next packet, since flex reads more bytes
 * before executing the action that does yyterminate(). */
#define YY_USER_ACTION do { yyextra->token.length = yyleng; } while (0);

#define NO_USER "<none>"

#ifndef HAVE_UNISTD_H
#define YY_NO_UNISTD_H
#endif

/*
 * Sleazy hack to suppress compiler warnings in yy_fatal_error().
 */
#define YY_EXIT_FAILURE ((void)yyscanner, 2)

/*
 * Macros for the allocators, to discard the extra argument.
 */
#define ascend_alloc(size, yyscanner)		(void *)malloc(size)
#define ascend_realloc(ptr, size, yyscanner)	(void *)realloc((char *)(ptr), (size))
#define ascend_free(ptr, yyscanner)		free((char *)ptr)

%}

D [0-9]
H [A-Fa-f0-9]

PPP_XPFX PPP-OUT
PPP_RPFX PPP-IN
ISDN_XPFX PRI-XMIT-
ISDN_RPFX PRI-RCV-
WAN_XPFX XMIT[\-:]*
WAN_RPFX RECV[\-:]*
ETHER_PFX ETHER

WDD_DATE    "Date:"
WDD_TIME    "Time:"
WDD_CAUSE   "Cause an attempt to place call to "
WDD_CALLNUM [^\n\r\t ]+
WDD_CHUNK   "WD_DIALOUT_DISP: chunk"
WDD_TYPE    "type "[^\n\r\t ]+

%s sc_gen_task
%s sc_gen_time_s
%s sc_gen_time_u
%s sc_gen_octets
%s sc_gen_counter
%s sc_gen_byte

%s sc_wds_user
%s sc_wds_sess

%s sc_wdd_date_d
%s sc_wdd_date_m
%s sc_wdd_date_y
%s sc_wdd_time
%s sc_wdd_time_h
%s sc_wdd_time_m
%s sc_wdd_time_s
%s sc_wdd_cause
%s sc_wdd_callnum
%s sc_wdd_chunk
%s sc_wdd_chunknum
%s sc_wdd_type

%s sc_chardisp

%s sc_isdn_call
%s sc_ether_direction

%%

<INITIAL,sc_gen_byte>{ETHER_PFX} {
    BEGIN(sc_ether_direction);
    yyextra->token.u16_val = ASCEND_PFX_ETHER;
    return ETHER_PREFIX;
}

<INITIAL,sc_gen_byte>{ISDN_XPFX} {
    BEGIN(sc_isdn_call);
    yyextra->token.u16_val = ASCEND_PFX_ISDN_X;
    return ISDN_PREFIX;
}

<INITIAL,sc_gen_byte>{ISDN_RPFX} {
    BEGIN(sc_isdn_call);
    yyextra->token.u16_val = ASCEND_PFX_ISDN_R;
    return ISDN_PREFIX;
}

<INITIAL,sc_gen_byte>{WAN_XPFX} {
    BEGIN(sc_wds_user);
    yyextra->token.u16_val = ASCEND_PFX_WDS_X;
    return WDS_PREFIX;
}

<INITIAL,sc_gen_byte>{WAN_RPFX} {
    BEGIN(sc_wds_user);
    yyextra->token.u16_val = ASCEND_PFX_WDS_R;
    return WDS_PREFIX;
}

<INITIAL,sc_gen_byte>{PPP_XPFX} {
    BEGIN(sc_wds_user);
    yyextra->token.u16_val = ASCEND_PFX_WDS_X;
    return WDS_PREFIX;
}

<INITIAL,sc_gen_byte>{PPP_RPFX} {
    BEGIN(sc_wds_user);
    yyextra->token.u16_val = ASCEND_PFX_WDS_R;
    return WDS_PREFIX;
}

 /*
  * If we allow an arbitrary non-zero number of non-left-parentheses after
  * "ETHER", that means that some file that has ETHER followed by a lot of
  * text (see, for example, tpncp/tpncp.dat in the source tree) can cause
  * either an infinite loop or a loop that take forever to finish, as the
  * scanner keeps swallowing characters.  Limit it to 20 characters.
  *
  * XXX - any reason to require at least two of them?
  */
<sc_ether_direction>[^\(]{2,20} {
    BEGIN(sc_gen_task);
    return STRING;
}

 /*
  * If we allow an arbitrary non-zero number of non-slash, non-left-parentheses,
  * non-colon characters after "PRI-XMIT", that means that some file that has
  * PRI-XMIT= followed by a lot of text can cause either an infinite loop or
  * a loop that take forever to finish, as the scanner keeps swallowing
  * characters.  Limit it to 20 characters.
  */
<sc_isdn_call>[^\/\(:]{1,20} {
    BEGIN(sc_gen_task);
    return DECNUM;
}

<sc_wds_user>[^:]{2,20} {
    char *atcopy = g_strdup(yytext);
    char colon = input(yyscanner);
    char after = input(yyscanner);
    int retval = STRING;

    unput(after); unput(colon);

    if (after != '(' && after != ' ') {
        BEGIN(sc_wds_sess);
        if (yyextra->pseudo_header != NULL && yyextra->pseudo_header->user[0] == '\0') {
        (void) g_strlcpy(yyextra->pseudo_header->user, atcopy, ASCEND_MAX_STR_LEN);
        }
    } else {	/* We have a version 7 file */
        BEGIN(sc_gen_task);
        if (yyextra->pseudo_header != NULL && yyextra->pseudo_header->user[0] == '\0') {
        (void) g_strlcpy(yyextra->pseudo_header->user, NO_USER, ASCEND_MAX_STR_LEN);
        }
        /* Are valid values ever > 2^32? If so we need to adjust YYSTYPE and a lot of */
        /* upstream code accordingly. */
        yyextra->token.u32_val = (guint32) strtoul(yytext, NULL, 10);
        retval = DECNUM;
    }
    g_free (atcopy);
    return retval;
}

<sc_wds_sess>{D}* {
    BEGIN(sc_gen_task);
    yyextra->token.u32_val = (guint32) strtoul(yytext, NULL, 10);
    return DECNUM;
}

<sc_gen_task>(0x|0X)?{H}{2,8} {
    BEGIN(sc_gen_time_s);
    yyextra->token.u32_val = (guint32) strtoul(yytext, NULL, 16);
    return HEXNUM;
}

<sc_gen_task>\"[A-Za-z0-9_ ]+\" {
    return STRING;
}

<sc_gen_time_s>{D}{1,10} {
    BEGIN(sc_gen_time_u);
    yyextra->token.u32_val = (guint32) strtoul(yytext, NULL, 10);
    return DECNUM;
}

<sc_gen_time_u>{D}{1,6} {
    char *atcopy = g_strdup(yytext);
    BEGIN(sc_gen_octets);
    /* only want the most significant 2 digits. convert to usecs */
    if (strlen(atcopy) > 2)
        atcopy[2] = '\0';
    yyextra->token.u32_val = (guint32) strtoul(atcopy, NULL, 10) * 10000;
    g_free(atcopy);
    return DECNUM;
}

<sc_gen_octets>{D}{1,10} {
    BEGIN(sc_gen_counter);
    yyextra->token.u32_val = (guint32) strtoul(yytext, NULL, 10);
    return DECNUM;
}

<sc_gen_counter,sc_gen_byte>"["{H}{4}"]:" {
    BEGIN(sc_gen_byte);
    return COUNTER;
}

<sc_gen_byte>{H}{2} {
    yyextra->token.u8_val = (guint8) strtoul(yytext, NULL, 16);
    return HEXBYTE;
}

<sc_gen_byte>" "{4} {
    BEGIN(sc_chardisp);
}

<sc_chardisp>.*	{
    BEGIN(sc_gen_byte);
}

<INITIAL,sc_gen_byte>{WDD_DATE} {
    BEGIN(sc_wdd_date_m);
    return WDD_DATE;
}

 /*
  * Scan m/d/y as three separate m, /d/, and y tokens.
  * We could alternately treat m/d/y as a single token.
  */
<sc_wdd_date_m>{D}{2} {
    BEGIN(sc_wdd_date_d);
    yyextra->token.u32_val = (guint32) strtoul(yytext, NULL, 10);
    return WDD_DECNUM;
}

<sc_wdd_date_d>\/{D}{2}\/ {
    BEGIN(sc_wdd_date_y);
    yyextra->token.u32_val = (guint32) strtoul(yytext+1, NULL, 10);
    return WDD_DECNUM;
}

<sc_wdd_date_y>{D}{4} {
    BEGIN(sc_wdd_time);
    yyextra->token.u32_val = (guint32) strtoul(yytext, NULL, 10);
    return WDD_DECNUM;
}

<sc_wdd_time>{WDD_TIME} {
    BEGIN(sc_wdd_time_h);
    return WDD_TIME;
}

 /*
  * Scan h:m:s as three separate h, :m:, and s tokens similar to above.
  */
<sc_wdd_time_h>{D}{2} {
    BEGIN(sc_wdd_time_m);
    yyextra->token.u32_val = (guint32) strtoul(yytext, NULL, 10);
    return WDD_DECNUM;
}

<sc_wdd_time_m>:{D}{2}: {
    BEGIN(sc_wdd_time_s);
    yyextra->token.u32_val = (guint32) strtoul(yytext+1, NULL, 10);
    return WDD_DECNUM;
}

<sc_wdd_time_s>{D}{2} {
    BEGIN(sc_wdd_cause);
    yyextra->token.u32_val = (guint32) strtoul(yytext, NULL, 10);
    return WDD_DECNUM;
}

<sc_wdd_cause>{WDD_CAUSE} {
    BEGIN(sc_wdd_callnum);
    return WDD_CAUSE;
}

<sc_wdd_callnum>{WDD_CALLNUM} {
    BEGIN(sc_wdd_chunk);
    (void) g_strlcpy(yyextra->token.str_val, yytext, ASCEND_MAX_STR_LEN);
    return WDD_CALLNUM;
}

<INITIAL,sc_wdd_chunk,sc_gen_byte>{WDD_CHUNK} {
    BEGIN(sc_wdd_chunknum);
    return WDD_CHUNK;
}

<sc_wdd_chunknum>{H}{1,8} {
    BEGIN(sc_wdd_type);
    yyextra->token.u32_val = (guint32) strtoul(yytext, NULL, 16);
    return HEXNUM;
}

<sc_wdd_type>{WDD_TYPE} {
    BEGIN(sc_gen_task);
    return KEYWORD;
}

<sc_gen_task>\/{D}+ {
    return SLASH_SUFFIX;
}

(0x|0X)?{H}+ { return HEXNUM; }

task:|task|at|time:|octets { return KEYWORD; }

<<EOF>> { yyterminate(); }

(.|\n) ;

%%

/*
 * Turn diagnostics back on, so we check the code that we've written.
 */
DIAG_ON_FLEX