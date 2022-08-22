/* 802_11-utils.c
 * 802.11 utility definitions
 *
 * Wireshark - Network traffic analyzer
 * By Gerald Combs <gerald@wireshark.org>
 * Copyright 2007 Gerald Combs
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#include "config.h"
#include "802_11-utils.h"

typedef struct freq_cvt_s {
    guint fmin;         /* Minimum frequency in MHz */
    guint fmax;         /* Maximum frequency in MHz */
    gint cmin;          /* Minimum/base channel */
    gboolean is_bg;     /* B/G channel? */
} freq_cvt_t;

#define FREQ_STEP 5     /* MHz. This seems to be consistent, thankfully */

/*
 * XXX - Japanese channels 182 through 196 actually have center
 * frequencies that are off by 2.5 MHz from these values, according
 * to the IEEE standard, although the table in ARIB STD T-71 version 5.2:
 *
 *     http://www.arib.or.jp/english/html/overview/doc/1-STD-T71v5_2.pdf
 *
 * section 5.3.8.3.3 doesn't show that.
 *
 * XXX - what about the U.S. public safety 4.9 GHz band?
 *
 * XXX - what about 802.11ad?
 */
static freq_cvt_t freq_cvt[] = {
    { 2412, 2472,   1, TRUE },  /* IEEE Std 802.11-2020: Section 15.4.4.3 and Annex E */
    { 2484, 2484,  14, TRUE },  /* IEEE Std 802.11-2020: Section 15.4.4.3 and Annex E */
    { 5000, 5925,   0, FALSE }, /* IEEE Std 802.11-2020: Annex E */
    { 5950, 7125,   0, FALSE }, /* IEEE Std 802.11ax-2021: Annex E */
    { 4910, 4980, 182, FALSE },
};

#define NUM_FREQ_CVT (sizeof(freq_cvt) / sizeof(freq_cvt_t))
#define MAX_CHANNEL(fc) ( (gint) ((fc.fmax - fc.fmin) / FREQ_STEP) + fc.cmin )

/*
 * Get channel number given a Frequency
 */
gint
ieee80211_mhz_to_chan(guint freq) {
    guint i;

    for (i = 0; i < NUM_FREQ_CVT; i++) {
        if (freq >= freq_cvt[i].fmin && freq <= freq_cvt[i].fmax) {
            return ((freq - freq_cvt[i].fmin) / FREQ_STEP) + freq_cvt[i].cmin;
        }
    }
    return -1;
}

/*
 * Get Frequency given a Channel number
 *
 * XXX - Because channel numbering schemes for 2.4 and 5 overlap with 6 GHz,
 * this function may not return the correct channel. For example, the frequency
 * for channel 1 in 2.4 GHz band is 2412 MHz, while the frequency for channel 1
 * in the 6 GHz band is 5955 MHz. To resolve this problem, this function needs
 * to take a starting frequency to convert channel to frequencies correctly.
 * Unfortunately, this is not possible in some cases, so for now, the order on
 * which frequency ranges are defined will favor 2.4 and 5 GHz over 6 GHz.
 */
guint
ieee80211_chan_to_mhz(gint chan, gboolean is_bg) {
    guint i;

    for (i = 0; i < NUM_FREQ_CVT; i++) {
        if (is_bg == freq_cvt[i].is_bg &&
                chan >= freq_cvt[i].cmin && chan <= MAX_CHANNEL(freq_cvt[i])) {
            return ((chan - freq_cvt[i].cmin) * FREQ_STEP) + freq_cvt[i].fmin;
        }
    }
    return 0;
}

/*
 * Get channel representation string given a Frequency
 */
gchar*
ieee80211_mhz_to_str(guint freq){
    gint chan = ieee80211_mhz_to_chan(freq);
    gboolean is_bg = FREQ_IS_BG(freq);

    if (chan < 0) {
        return ws_strdup_printf("%u", freq);
    } else {
        return ws_strdup_printf("%u [%s %u]", freq, is_bg ? "BG" : "A",
            chan);
    }
}

/*
 * Editor modelines
 *
 * Local Variables:
 * c-basic-offset: 4
 * tab-width: 8
 * indent-tabs-mode: nil
 * End:
 *
 * ex: set shiftwidth=4 tabstop=8 expandtab:
 * :indentSize=4:tabSize=8:noTabs=true:
 */
