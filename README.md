# GXAS

*This is the way you can make your UNISTIM phones show applications on their screen.*

*This is... not Nortel?*

Nortel Unistim phones (like the i2007 or 1140) can show remote applications via
a variant of VNC. The official server for this was sold to Citrix and lost, but
there was a primitive alternative created by a Russian company. Unfortunately,
this is no longer developed either, and restricted you to their applications.

This provides an implementation of what's needed to implement GXAS and defer
to a real VNC server.

## Protocol details

There are two connections; configuration, then it opens connection. Both start
with an HTTP request, but after that, become either a control channel (config)
and a connection channel (to the VNC server)

The application list claims to be `text/xml`, but is in fact a custom format
with `$` separated values:

* Internal app name?
* Friendly app name? (padded?)
* Soft key labels
* Unknown single-digit numeric
* Autostart (0/1)
* PNG length
* PNG

The VNC connection is mostly normal, except:

* The client version packet has a null instead of a newline
* It's picky w/ cursors and will drop the connection if it gets confused
* Colour maps may be problematic (or a false alarm caused by)
* Mostly 

## TODO

* Share Wireshark captures of RFBServer
* Get Xvnc working properly
  * With patches, can connect and send input, but nothing displays
* Figure out VNC extensions
* Start Xvnc as an inetd service, so we can consume stdio instead
* Show own app list (instead of repeating a captured RFBServer)
* Distinguish and authenticate phones
* Multiple applications (likely spawned by own Xvnc, put under OTP supervisor)
* Figure out control protocol

## TigerVNC patchset

Likely overkill.

```diff
diff --git a/common/rfb/ClientParams.cxx b/common/rfb/ClientParams.cxx
index 6f075a24..81c7d6ec 100644
--- a/common/rfb/ClientParams.cxx
+++ b/common/rfb/ClientParams.cxx
@@ -171,14 +171,14 @@ void ClientParams::setClipboardCaps(rdr::U32 flags, const rdr::U32* lengths)
 
 bool ClientParams::supportsLocalCursor() const
 {
-  if (supportsEncoding(pseudoEncodingCursorWithAlpha))
-    return true;
-  if (supportsEncoding(pseudoEncodingVMwareCursor))
-    return true;
-  if (supportsEncoding(pseudoEncodingCursor))
-    return true;
-  if (supportsEncoding(pseudoEncodingXCursor))
-    return true;
+  //if (supportsEncoding(pseudoEncodingCursorWithAlpha))
+  //  return true;
+  //if (supportsEncoding(pseudoEncodingVMwareCursor))
+  //  return true;
+  //if (supportsEncoding(pseudoEncodingCursor))
+  //  return true;
+  //if (supportsEncoding(pseudoEncodingXCursor))
+  //  return true;
   return false;
 }
 
diff --git a/common/rfb/SConnection.cxx b/common/rfb/SConnection.cxx
index 8277844c..b8c6535d 100644
--- a/common/rfb/SConnection.cxx
+++ b/common/rfb/SConnection.cxx
@@ -500,8 +500,8 @@ void SConnection::setPixelFormat(const PixelFormat& pf)
 {
   SMsgHandler::setPixelFormat(pf);
   readyForSetColourMapEntries = true;
-  if (!pf.trueColour)
-    writeFakeColourMap();
+  //if (!pf.trueColour)
+  //  writeFakeColourMap();
 }
 
 void SConnection::framebufferUpdateRequest(const Rect& r, bool incremental)
@@ -509,7 +509,7 @@ void SConnection::framebufferUpdateRequest(const Rect& r, bool incremental)
   if (!readyForSetColourMapEntries) {
     readyForSetColourMapEntries = true;
     if (!client.pf().trueColour) {
-      writeFakeColourMap();
+      //writeFakeColourMap();
     }
   }
 }
```

## Build and run

```shell
mix deps.get
mix compile
iex -S mix
```
