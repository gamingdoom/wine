/*
 * Copyright 2015 Andrew Eikum for CodeWeavers
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA
 */

#include "config.h"

#include <gst/gst.h>

#include "wine/list.h"

#include "gst_cbs.h"

/* gstreamer calls our callbacks from threads that Wine did not create. Some
 * callbacks execute code which requires Wine to have created the thread
 * (critical sections, debug logging, dshow client code). Since gstreamer can't
 * provide an API to override its thread creation, we have to intercept all
 * callbacks in code which avoids the Wine thread requirement, and then
 * dispatch those callbacks on a thread that is known to be created by Wine.
 *
 * This file must not contain any code that depends on the Wine TEB!
 */

static void call_cb(struct cb_data *cbdata)
{
    pthread_mutex_init(&cbdata->lock, NULL);
    pthread_cond_init(&cbdata->cond, NULL);
    cbdata->finished = 0;

    if(is_wine_thread()){
        /* The thread which triggered gstreamer to call this callback may
         * already hold a critical section. If so, executing the callback on a
         * worker thread can cause a deadlock. If  we are already on a Wine
         * thread, then there is no need to run this callback on a worker
         * thread anyway, which avoids the deadlock issue. */
        perform_cb(NULL, cbdata);

        pthread_cond_destroy(&cbdata->cond);
        pthread_mutex_destroy(&cbdata->lock);

        return;
    }

    pthread_mutex_lock(&cb_list_lock);

    list_add_tail(&cb_list, &cbdata->entry);
    pthread_cond_broadcast(&cb_list_cond);

    pthread_mutex_lock(&cbdata->lock);

    pthread_mutex_unlock(&cb_list_lock);

    while(!cbdata->finished)
        pthread_cond_wait(&cbdata->cond, &cbdata->lock);

    pthread_mutex_unlock(&cbdata->lock);

    pthread_cond_destroy(&cbdata->cond);
    pthread_mutex_destroy(&cbdata->lock);
}

GstBusSyncReply watch_bus_wrapper(GstBus *bus, GstMessage *msg, gpointer user)
{
    struct cb_data cbdata = { WATCH_BUS };

    cbdata.u.watch_bus_data.bus = bus;
    cbdata.u.watch_bus_data.msg = msg;
    cbdata.u.watch_bus_data.user = user;

    call_cb(&cbdata);

    return cbdata.u.watch_bus_data.ret;
}

void existing_new_pad_wrapper(GstElement *bin, GstPad *pad, gpointer user)
{
    struct cb_data cbdata = { EXISTING_NEW_PAD };

    cbdata.u.existing_new_pad_data.bin = bin;
    cbdata.u.existing_new_pad_data.pad = pad;
    cbdata.u.existing_new_pad_data.user = user;

    call_cb(&cbdata);
}

gboolean query_function_wrapper(GstPad *pad, GstObject *parent, GstQuery *query)
{
    struct cb_data cbdata = { QUERY_FUNCTION };

    cbdata.u.query_function_data.pad = pad;
    cbdata.u.query_function_data.parent = parent;
    cbdata.u.query_function_data.query = query;

    call_cb(&cbdata);

    return cbdata.u.query_function_data.ret;
}

gboolean activate_mode_wrapper(GstPad *pad, GstObject *parent, GstPadMode mode, gboolean activate)
{
    struct cb_data cbdata = { ACTIVATE_MODE };

    cbdata.u.activate_mode_data.pad = pad;
    cbdata.u.activate_mode_data.parent = parent;
    cbdata.u.activate_mode_data.mode = mode;
    cbdata.u.activate_mode_data.activate = activate;

    call_cb(&cbdata);

    return cbdata.u.activate_mode_data.ret;
}

void no_more_pads_wrapper(GstElement *decodebin, gpointer user)
{
    struct cb_data cbdata = { NO_MORE_PADS };

    cbdata.u.no_more_pads_data.decodebin = decodebin;
    cbdata.u.no_more_pads_data.user = user;

    call_cb(&cbdata);
}

GstFlowReturn request_buffer_src_wrapper(GstPad *pad, GstObject *parent, guint64 ofs, guint len,
        GstBuffer **buf)
{
    struct cb_data cbdata = { REQUEST_BUFFER_SRC };

    cbdata.u.request_buffer_src_data.pad = pad;
    cbdata.u.request_buffer_src_data.parent = parent;
    cbdata.u.request_buffer_src_data.ofs = ofs;
    cbdata.u.request_buffer_src_data.len = len;
    cbdata.u.request_buffer_src_data.buf = buf;

    call_cb(&cbdata);

    return cbdata.u.request_buffer_src_data.ret;
}

gboolean event_src_wrapper(GstPad *pad, GstObject *parent, GstEvent *event)
{
    struct cb_data cbdata = { EVENT_SRC };

    cbdata.u.event_src_data.pad = pad;
    cbdata.u.event_src_data.parent = parent;
    cbdata.u.event_src_data.event = event;

    call_cb(&cbdata);

    return cbdata.u.event_src_data.ret;
}

gboolean event_sink_wrapper(GstPad *pad, GstObject *parent, GstEvent *event)
{
    struct cb_data cbdata = { EVENT_SINK };

    cbdata.u.event_sink_data.pad = pad;
    cbdata.u.event_sink_data.parent = parent;
    cbdata.u.event_sink_data.event = event;

    call_cb(&cbdata);

    return cbdata.u.event_sink_data.ret;
}

GstFlowReturn got_data_sink_wrapper(GstPad *pad, GstObject *parent, GstBuffer *buf)
{
    struct cb_data cbdata = { GOT_DATA_SINK };

    cbdata.u.got_data_sink_data.pad = pad;
    cbdata.u.got_data_sink_data.parent = parent;
    cbdata.u.got_data_sink_data.buf = buf;

    call_cb(&cbdata);

    return cbdata.u.got_data_sink_data.ret;
}

GstFlowReturn got_data_wrapper(GstPad *pad, GstObject *parent, GstBuffer *buf)
{
    struct cb_data cbdata = { GOT_DATA };

    cbdata.u.got_data_data.pad = pad;
    cbdata.u.got_data_data.parent = parent;
    cbdata.u.got_data_data.buf = buf;

    call_cb(&cbdata);

    return cbdata.u.got_data_data.ret;
}

void removed_decoded_pad_wrapper(GstElement *bin, GstPad *pad, gpointer user)
{
    struct cb_data cbdata = { REMOVED_DECODED_PAD };

    cbdata.u.removed_decoded_pad_data.bin = bin;
    cbdata.u.removed_decoded_pad_data.pad = pad;
    cbdata.u.removed_decoded_pad_data.user = user;

    call_cb(&cbdata);
}

GstAutoplugSelectResult autoplug_blacklist_wrapper(GstElement *bin, GstPad *pad,
        GstCaps *caps, GstElementFactory *fact, gpointer user)
{
    struct cb_data cbdata = { AUTOPLUG_BLACKLIST };

    cbdata.u.autoplug_blacklist_data.bin = bin;
    cbdata.u.autoplug_blacklist_data.pad = pad;
    cbdata.u.autoplug_blacklist_data.caps = caps;
    cbdata.u.autoplug_blacklist_data.fact = fact;
    cbdata.u.autoplug_blacklist_data.user = user;

    call_cb(&cbdata);

    return cbdata.u.autoplug_blacklist_data.ret;
}

void unknown_type_wrapper(GstElement *bin, GstPad *pad, GstCaps *caps, gpointer user)
{
    struct cb_data cbdata = { UNKNOWN_TYPE };

    cbdata.u.unknown_type_data.bin = bin;
    cbdata.u.unknown_type_data.pad = pad;
    cbdata.u.unknown_type_data.caps = caps;
    cbdata.u.unknown_type_data.user = user;

    call_cb(&cbdata);
}

void release_sample_wrapper(gpointer data)
{
    struct cb_data cbdata = { RELEASE_SAMPLE };

    cbdata.u.release_sample_data.data = data;

    call_cb(&cbdata);
}

void Gstreamer_transform_pad_added_wrapper(GstElement *filter, GstPad *pad, gpointer user)
{
    struct cb_data cbdata = { TRANSFORM_PAD_ADDED };

    cbdata.u.transform_pad_added_data.filter = filter;
    cbdata.u.transform_pad_added_data.pad = pad;
    cbdata.u.transform_pad_added_data.user = user;

    call_cb(&cbdata);
}

gboolean query_sink_wrapper(GstPad *pad, GstObject *parent, GstQuery *query)
{
    struct cb_data cbdata = { QUERY_SINK };

    cbdata.u.query_sink_data.pad = pad;
    cbdata.u.query_sink_data.parent = parent;
    cbdata.u.query_sink_data.query = query;

    call_cb(&cbdata);

    return cbdata.u.query_sink_data.ret;
}
