#tag Class
Protected Class IDECommunicator
	#tag Method, Flags = &h0
		Sub Constructor()
		  mTagCounter = 0
		  mSocketPath = FindIPCPath
		  LastErrorMessage = ""
		  mConnected = False
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function CandidateSocketPaths() As String()
		  /// The path that last worked first, then the platform's candidates in the
		  /// order the IDE itself considers them. See Platform.IPCSocketPaths.
		  
		  Var paths() As String
		  paths.Add(mSocketPath)
		  
		  For Each p As String In Platform.IPCSocketPaths
		    paths.Add(p)
		  Next p
		  
		  Var unique() As String
		  For Each p As String In paths
		    If p.Trim = "" Then Continue
		    If Not ContainsString(unique, p) Then unique.Add(p)
		  Next p
		  
		  Return unique
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ContainsString(values() As String, target As String) As Boolean
		  For Each value As String In values
		    If value = target Then Return True
		  Next value
		  
		  Return False
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function FindIPCPath() As String
		  /// The path the IDE is most likely listening on. Platform.IPCSocketPaths
		  /// probes candidate FOLDERS for writability rather than testing the socket
		  /// path itself, which is the only form that works on Windows.
		  
		  Var paths() As String = Platform.IPCSocketPaths
		  If paths.Count > 0 Then Return paths(0)
		  
		  Return ""
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function NextTag() As String
		  /// Returns a unique tag string for each request to correlate requests with responses.

		  mTagCounter = mTagCounter + 1
		  Return "xmcp_" + mTagCounter.ToString

		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub Reconnect()
		  /// Reconnect to the Xojo IDE.

		  mSocketPath = FindIPCPath
		  LastErrorMessage = ""
		  mConnected = False

		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function SendAndReceive(script As String, timeoutMS As Integer = 10000) As JSONItem
		  /// Sends an IDE script and waits synchronously for the tagged response.
		  /// Uses IPCSocket transport only.
		  /// Returns the response JSON or Nil on timeout.
		  ///
		  /// Retries up to kMaxRetries times with a short pause if the socket is
		  /// temporarily unavailable (e.g. after the Xojo IDE navigates to a new
		  /// item) and the failure happened before the script was written to the
		  /// socket. Once the script has actually been sent, a subsequent failure
		  /// (e.g. timeout waiting for the response) is NOT retried, since the IDE
		  /// may have already executed it — resending could run it twice.

		  LastErrorMessage = ""
		  mParkedThisRequest = False
		  
		  // A request the IDE has accepted but not answered is still being executed: the
		  // IDE runs scripts one at a time on its main thread, and a build (or a modal
		  // dialog) holds it for minutes. Sending another request now would only queue it
		  // behind that one and give up on it too. Say so instead; DrainPending notices
		  // when the IDE has caught up and the next call goes through normally.
		  If DrainPending > 0 Then
		    LastErrorMessage = "The Xojo IDE is still executing an earlier request and has not answered it yet:" + _
		    EndOfLine + PendingSummary + EndOfLine + _
		    "No new request was sent. A build blocks the IDE until it finishes; wait for it, then try again."
		    LogVerbose("IDE request refused: " + LastErrorMessage)
		    Return Nil
		  End If
		  
		  Var tag As String = NextTag

		  // Build protocol upgrade + script request.
		  Var proto As New JSONItem
		  proto.Value("protocol") = 2

		  Var req As New JSONItem
		  req.Value("tag") = tag
		  req.Value("script") = script

		  Var payload As String = proto.ToString + Chr(0) + req.ToString + Chr(0)
		  LogVerbose("IDE request " + tag + ": trying IPCSocket transport.")

		  Const kMaxRetries = 5
		  Const kRetryPauseMS = 1000

		  Var attempt As Integer = 0
		  While attempt < kMaxRetries
		    attempt = attempt + 1

		    Var socketErrors() As String
		    For Each candidatePath As String In CandidateSocketPaths
		      LogVerbose("IDE request " + tag + ": IPCSocket path " + candidatePath + " (attempt " + attempt.ToString + ")")
		      Var responseViaSocket As JSONItem = SendAndReceiveViaIPCSocket(candidatePath, payload, tag, timeoutMS, script)
		      If responseViaSocket <> Nil Then
		        mConnected = True
		        mSocketPath = candidatePath
		        LastErrorMessage = ""
		        LogVerbose("IDE request " + tag + ": success via IPCSocket (" + candidatePath + ").")
		        Return responseViaSocket
		      End If

		      If LastErrorMessage <> "" Then
		        LogVerbose("IDE request " + tag + ": IPCSocket failed (" + candidatePath + "): " + LastErrorMessage)
		        socketErrors.Add(LastErrorMessage)
		      End If
		      
		      // The request was delivered and is now parked: the IDE has it and will execute
		      // it. Trying the remaining candidate paths - on macOS the same socket under
		      // other names - would only knock on a busy IDE again and clutter the message
		      // with "no listener" noise that is not the problem.
		      If mParkedThisRequest Then Exit
		    Next candidatePath
		    
		    If mParkedThisRequest Then
		      mParkedThisRequest = False
		      LastErrorMessage = String.FromArray(socketErrors, " | ")
		      Exit While
		    End If
		    
		    // All paths failed. If the socket was simply not found (IDE temporarily
		    // closed it after a navigation), wait briefly and retry.
		    Var allNotFound As Boolean = True
		    For Each err As String In socketErrors
		      If Not err.BeginsWith(kNoListenerPrefix) Then
		        allNotFound = False
		        Exit
		      End If
		    Next err

		    If attempt < kMaxRetries And (socketErrors.Count = 0 Or allNotFound) Then
		      LogVerbose("IDE request " + tag + ": socket temporarily unavailable, retrying in " + kRetryPauseMS.ToString + "ms...")
		      Var pauseDeadline As Double = System.Microseconds + (kRetryPauseMS * 1000.0)
		      While System.Microseconds < pauseDeadline
		        App.SleepCurrentThread(10)
		      Wend
		    Else
		      If socketErrors.Count > 0 Then
		        LastErrorMessage = String.FromArray(socketErrors, " | ")
		      Else
		        LastErrorMessage = "No IPCSocket response from Xojo IDE within " + timeoutMS.ToString + _
		        "ms. Searched: " + Platform.SocketPathSummary
		      End If
		      Exit While
		    End If
		  Wend

		  LogVerbose("IDE request " + tag + ": failed. " + LastErrorMessage)

		  mConnected = False
		  Return Nil

		End Function
	#tag EndMethod
	
	#tag Method, Flags = &h0
		Function RunScript(script As String, timeoutMS As Integer = 10000) As MCPKit.ToolResult
		  /// Sends an IDE script and converts the response into a ToolResult.
		  /// Handles the common contract used by most tools:
		  ///   - Nil response → Failure with LastErrorMessage (or timeout message)
		  ///   - response.response as string starting with "ERROR:" → Failure
		  ///   - response.response as any other string → Success(string)
		  ///   - response.response as JSON object with `scriptError` or `buildError` key → Failure
		  ///   - response.response as any other JSON object → Success(json.ToString)
		  /// None of RunScript's callers send scripts whose Print output is a
		  /// buildError/scriptError-shaped JSON string (that only happens via
		  /// DoCommand "RunApp"/"BuildApp", which bypass RunScript and call
		  /// SendAndReceive directly) — so a string response is never re-parsed
		  /// as JSON here. Doing so previously misclassified legitimate text
		  /// content (e.g. a constant or description whose value happens to
		  /// contain the literal text `{"buildError":...}`) as a Failure.

		  Var response As JSONItem = SendAndReceive(script, timeoutMS)
		  If response = Nil Then
		    If LastErrorMessage <> "" Then
		      Return MCPKit.ToolResult.Failure(LastErrorMessage)
		    End If
		    Return MCPKit.ToolResult.Failure("Timeout waiting for IDE response.")
		  End If

		  If Not response.HasKey("response") Then
		    Return MCPKit.ToolResult.Failure("Unexpected response from IDE: " + response.ToString)
		  End If

		  Var resp As String
		  Var respVar As Variant = response.Value("response")
		  If respVar.Type = Variant.TypeString Then
		    resp = respVar.StringValue
		  Else
		    Var respJSON As JSONItem = response.Value("response")
		    // The IDE returns structured failures as a JSON object with a
		    // `scriptError` key (e.g. compile errors in the script we sent) or
		    // a `buildError` key (e.g. DoCommand "BuildApp"/"RunApp" failures).
		    // These must be surfaced as Failure, not stringified as Success.
		    If respJSON.HasKey("scriptError") Then
		      Return MCPKit.ToolResult.Failure("IDE script error: " + respJSON.ToString)
		    End If
		    If respJSON.HasKey("buildError") Then
		      Return MCPKit.ToolResult.Failure("IDE build error: " + respJSON.ToString)
		    End If
		    // The IDE encodes a script that printed an empty string as an empty
		    // JSON object ({}) rather than an empty string — normalize it back
		    // so callers see "" instead of the misleading literal text "{}".
		    If respJSON.Count = 0 Then
		      resp = ""
		    Else
		      resp = respJSON.ToString
		    End If
		  End If

		  If resp.BeginsWith("ERROR:") Then
		    Return MCPKit.ToolResult.Failure(resp)
		  End If

		  Return MCPKit.ToolResult.Success(resp)

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub LogVerbose(message As String)
		  If App <> Nil And App.Verbose Then
		    System.DebugLog(message)
		  End If
		End Sub
	#tag EndMethod
	
	#tag Method, Flags = &h21
		Private Function SendAndReceiveViaIPCSocket(candidatePath As String, payload As String, tag As String, timeoutMS As Integer, script As String) As JSONItem
		  LastErrorMessage = ""

		  #If Not TargetWindows Then
		    // A Unix domain socket is a real filesystem entry, so a missing file means the
		    // IDE is definitely not listening here and the connect can be skipped entirely.
		    // Never do this on Windows: an IPCSocket endpoint there is not a file but a TCP
		    // socket on localhost whose port is derived from the path string, so Exists is
		    // always False even while the IDE is listening.
		    Var socketFile As New FolderItem(candidatePath, FolderItem.PathModes.Native)
		    If socketFile = Nil Or Not socketFile.Exists Then
		      LastErrorMessage = kNoListenerPrefix + " at " + candidatePath + " (no socket file)."
		      Return Nil
		    End If
		  #EndIf

		  Var deadlineUS As Double = System.Microseconds + (timeoutMS * 1000.0)
		  Var sock As New IPCSocket
		  sock.Path = candidatePath

		  Try
		    sock.Connect
		  Catch e As RuntimeException
		    // Whether this counts as 'nobody is listening' - and so as retryable - differs
		    // by platform. Off Windows the Exists check above already ruled out a missing
		    // socket, so a failed connect means something more specific (a stale socket from
		    // a crashed IDE, a permission problem) and is reported as fatal, unchanged from
		    // before. On Windows there is no such check to lean on, so a failed connect is
		    // the only evidence that nothing is listening on this candidate.
		    #If TargetWindows Then
		      LastErrorMessage = kNoListenerPrefix + " at " + candidatePath + ": " + e.Message
		    #Else
		      LastErrorMessage = "IPCSocket connect failed for " + candidatePath + ": " + e.Message
		    #EndIf
		    Return Nil
		  End Try
		  
		  // Bound the connect wait separately from the response wait. Without a socket file
		  // to pre-check, a wrong candidate can only be ruled out by a failed connect, and a
		  // build request would otherwise sit here for its full 120s timeout on every
		  // candidate before reaching the one the IDE is listening on.
		  Var connectTimeoutMS As Integer = timeoutMS
		  If connectTimeoutMS > kConnectTimeoutMS Then connectTimeoutMS = kConnectTimeoutMS
		  Var connectDeadlineUS As Double = System.Microseconds + (connectTimeoutMS * 1000.0)
		  
		  While Not sock.IsConnected And System.Microseconds < connectDeadlineUS
		    sock.Poll
		    App.SleepCurrentThread(5)
		  Wend
		  
		  If Not sock.IsConnected Then
		    sock.Close
		    #If TargetWindows Then
		      LastErrorMessage = kNoListenerPrefix + " at " + candidatePath + _
		      " (connect timed out after " + connectTimeoutMS.ToString + "ms)."
		    #Else
		      LastErrorMessage = "IPCSocket connect timed out for " + candidatePath + _
		      " after " + connectTimeoutMS.ToString + "ms."
		    #EndIf
		    Return Nil
		  End If

		  // Once Write succeeds, the IDE may have already received (and be
		  // executing) the script even if we never see a response — e.g. a
		  // timeout below. From this point on, a failure must NOT be treated
		  // as safe to blindly retry with the same script.
		  Try
		    sock.Write(payload)
		    sock.Flush
		  Catch e As RuntimeException
		    sock.Close
		    LastErrorMessage = "IPCSocket write failed for " + candidatePath + ": " + e.Message
		    Return Nil
		  End Try

		  Var buffer As String = ""
		  Var hadData As Boolean = False
		  
		  // One reply can arrive as several messages under the same tag: a script's Print
		  // output and a compiler warning about it land about a millisecond apart, and an
		  // analysis returns its buildError and the Print sentinel together. Returning on
		  // the first frame made the answer whichever part won the race. After the first
		  // matching frame the loop keeps reading for a short window and MergeReply folds
		  // the parts. When the first part is only a warning the real output is still
		  // coming and may take as long as the script itself, so that wait is longer and
		  // ends as soon as any further part arrives.
		  Var frames() As JSONItem
		  Var collectUntilUS As Double = deadlineUS
		  
		  While System.Microseconds < deadlineUS And System.Microseconds < collectUntilUS
		    sock.Poll

		    Var chunk As String = sock.ReadAll
		    If chunk = "" Then
		      App.SleepCurrentThread(5)
		      Continue
		    End If
		    
		    hadData = True
		    buffer = buffer + chunk
		    
		    Var nulPos As Integer = buffer.IndexOf(Chr(0))
		    While nulPos >= 0
		      Var frame As String = buffer.Left(nulPos).Trim
		      buffer = buffer.Middle(nulPos + 1)
		      nulPos = buffer.IndexOf(Chr(0))
		      
		      If frame = "" Then Continue
		      
		      Try
		        Var response As New JSONItem(frame)
		        If response.HasKey("tag") And response.Value("tag").StringValue = tag Then
		          frames.Add(response)
		          If frames.Count = 1 Then
		            If ReplyKind(response) = "warning" Then
		              collectUntilUS = System.Microseconds + (kSplitWaitForOutputMS * 1000.0)
		            Else
		              collectUntilUS = System.Microseconds + (kSplitReplyWindowMS * 1000.0)
		            End If
		          ElseIf ReplyKind(frames(0)) = "warning" Then
		            // The output the warning was holding up has arrived; nothing else is coming.
		            collectUntilUS = System.Microseconds
		          End If
		        Else
		          LogVerbose("IDE request " + tag + ": ignoring a frame for another tag (stale or unsolicited).")
		        End If
		      Catch e As JSONException
		        // Ignore malformed chunks and continue.
		      End Try
		    Wend
		  Wend
		  
		  If frames.Count > 0 Then
		    sock.Close
		    LastErrorMessage = ""
		    Return MergeReply(frames)
		  End If
		  
		  If hadData Then
		    sock.Close
		    LastErrorMessage = "Received IPC data from " + candidatePath + ", but no matching tag was found for " + tag + "."
		    Return Nil
		  End If
		  
		  // The IDE accepted the request - connect and write both succeeded - and has not
		  // answered within the timeout. Do NOT close the socket. The IDE will answer when
		  // it is done, and a write into a closed peer raises SIGPIPE, which the Xojo IDE
		  // does not ignore: it dies mid-build, with no crash report. Park the socket open
		  // instead; DrainPending releases it once the IDE has replied or has gone away.
		  AddPending(sock, tag, script)
		  mParkedThisRequest = True
		  LastErrorMessage = "The Xojo IDE accepted the request but has not answered within " + timeoutMS.ToString + _
		  "ms. It is most likely busy - a build, or a modal dialog waiting for a click - and it will finish " + _
		  "the request regardless. The connection is kept open so the IDE can reply safely; that reply will " + _
		  "be discarded. Further requests are refused until the IDE has answered."
		  
		  Return Nil
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function ReplyKind(envelope As JSONItem) As String
		  /// Classifies one reply envelope by what its "response" carries:
		  ///   "output"  - a string (what the script printed), or an object that is none of the below
		  ///   "empty"   - an empty object: the IDE's answer to a script that printed nothing
		  ///   "warning" - diagnostics that are warnings only; the script or build still ran
		  ///   "error"   - scriptError with errors, buildError with errors, missingFiles, openErrors, loadError
		  ///   "unknown" - no "response" key at all
		  ///
		  /// scriptError is a heterogeneous array: each entry has a "type" that is
		  /// scriptCompilerError, scriptRuntimeError or scriptCompilerWarning, and a reply that
		  /// carries only warnings means the script compiled and ran. Treating the whole array as
		  /// fatal reported failures for scripts that had worked.
		  
		  If envelope = Nil Or Not envelope.HasKey("response") Then Return "unknown"
		  
		  Var resp As Variant = envelope.Value("response")
		  If resp.Type = Variant.TypeString Then Return "output"
		  
		  Var obj As JSONItem
		  Try
		    obj = envelope.Value("response")
		  Catch e As RuntimeException
		    Return "output"
		  End Try
		  If obj = Nil Then Return "output"
		  If obj.Count = 0 Then Return "empty"
		  
		  If obj.HasKey("scriptError") Then
		    Var items As JSONItem = obj.Value("scriptError")
		    If items <> Nil And items.IsArray Then
		      For i As Integer = 0 To items.Count - 1
		        Var entry As JSONItem = items.ChildAt(i)
		        Var kind As String = If(entry <> Nil And entry.HasKey("type"), entry.Value("type").StringValue, "")
		        If Not kind.Lowercase.EndsWith("warning") Then Return "error"
		      Next i
		      Return "warning"
		    End If
		    Return "error"
		  End If
		  
		  If obj.HasKey("buildError") Then
		    Var be As JSONItem = obj.Value("buildError")
		    If be <> Nil And be.HasKey("errors") Then
		      Var errs As JSONItem = be.Value("errors")
		      If errs <> Nil And errs.Count > 0 Then Return "error"
		    End If
		    If be <> Nil And be.HasKey("warnings") Then
		      Var warns As JSONItem = be.Value("warnings")
		      If warns <> Nil And warns.Count > 0 Then Return "warning"
		    End If
		    Return "empty"
		  End If
		  
		  If obj.HasKey("missingFiles") Or obj.HasKey("openErrors") Or obj.HasKey("loadError") Then Return "error"
		  
		  Return "output"
		End Function
	#tag EndMethod
	#tag Method, Flags = &h0
		Function ReplyDiagnostics(envelope As JSONItem) As String
		  /// The reply's blocking diagnostics as readable text, or "" when there are none -
		  /// that is, when the reply is output, empty, or warnings only. Covers every error
		  /// shape the IDE is known to send: scriptError (errors only; warnings are for
		  /// ReplyWarnings), buildError.errors, missingFiles, openErrors and loadError.
		  ///
		  /// missingFiles is undocumented but real: an Android build with no key store answers
		  /// {"missingFiles": "Unable to build. Please specify a Key Store properties file..."},
		  /// a precise message that used to be dropped as an unrecognised object.
		  
		  If ReplyKind(envelope) <> "error" Then Return ""
		  
		  Var obj As JSONItem = envelope.Value("response")
		  Var lines() As String
		  
		  If obj.HasKey("scriptError") Then
		    Var text As String = FormatScriptErrors(obj.Value("scriptError"), False)
		    If text <> "" Then lines.Add("Script errors:" + EndOfLine + text)
		  End If
		  If obj.HasKey("buildError") Then
		    Var be As JSONItem = obj.Value("buildError")
		    If be <> Nil And be.HasKey("errors") Then
		      Var errs As JSONItem = be.Value("errors")
		      If errs <> Nil And errs.Count > 0 Then
		        lines.Add("Build errors (" + errs.Count.ToString + "):" + EndOfLine + FormatDiagnosticList(errs, "Error"))
		      End If
		    End If
		  End If
		  If obj.HasKey("missingFiles") Then
		    lines.Add("The IDE needs something configured before it can build: " + obj.Value("missingFiles").StringValue)
		  End If
		  If obj.HasKey("openErrors") Then
		    lines.Add("The project reported errors while opening: " + JSONItem(obj.Value("openErrors")).ToString)
		  End If
		  If obj.HasKey("loadError") Then
		    lines.Add("The project could not be loaded: " + JSONItem(obj.Value("loadError")).ToString)
		  End If
		  
		  If lines.Count = 0 Then Return "The IDE returned an error: " + obj.ToString
		  Return String.FromArray(lines, EndOfLine)
		End Function
	#tag EndMethod
	#tag Method, Flags = &h0
		Function ReplyWarnings(envelope As JSONItem) As String
		  /// Warnings carried by the reply - in its primary part or in any part MergeReply
		  /// attached - as readable text, or "" when there are none. For a successful script
		  /// this is typically a scriptCompilerWarning about the script XMCP itself sent.
		  
		  If envelope = Nil Then Return ""
		  Var lines() As String
		  
		  Var candidates() As JSONItem
		  If envelope.HasKey("response") And envelope.Value("response").Type <> Variant.TypeString Then
		    Try
		      candidates.Add(JSONItem(envelope.Value("response")))
		    Catch e As RuntimeException
		    End Try
		  End If
		  If envelope.HasKey("xmcp_parts") Then
		    Var parts As JSONItem = envelope.Value("xmcp_parts")
		    For i As Integer = 0 To parts.Count - 1
		      Try
		        // Only objects. MergeReply attaches the other parts' response VALUES, and
		        // for a multi-Print script those are plain strings - asking one of those
		        // HasKey raises, and the exception escaped as a JSON-RPC parse error.
		        Var child As JSONItem = parts.ChildAt(i)
		        If child <> Nil And Not child.IsArray Then candidates.Add(child)
		      Catch e As RuntimeException
		      End Try
		    Next i
		  End If
		  
		  For Each obj As JSONItem In candidates
		    If obj = Nil Or obj.IsArray Then Continue
		    
		    // A reply part can be any JSON the IDE chose to send. Reading warnings out of
		    // one must never fail the whole request: there is nothing to report from a part
		    // that is not an object, and that is not an error.
		    Try
		      If obj.HasKey("scriptError") Then
		        Var text As String = FormatScriptErrors(obj.Value("scriptError"), True)
		        If text <> "" Then lines.Add(text)
		      End If
		      If obj.HasKey("buildError") Then
		        Var be As JSONItem = obj.Value("buildError")
		        If be <> Nil And be.HasKey("warnings") Then
		          Var warns As JSONItem = be.Value("warnings")
		          If warns <> Nil And warns.Count > 0 Then lines.Add(FormatDiagnosticList(warns, "Warning"))
		        End If
		      End If
		    Catch e As RuntimeException
		    End Try
		  Next obj
		  
		  Return String.FromArray(lines, EndOfLine)
		End Function
	#tag EndMethod
	#tag Method, Flags = &h21
		Private Function FormatScriptErrors(items As JSONItem, warningsOnly As Boolean) As String
		  /// One line per scriptError entry of the requested severity. The IDE wraps the
		  /// script in a line of boilerplate before compiling it, so every line number it
		  /// reports is one greater than the line that was sent; that offset is removed here.
		  /// A line too small to carry the offset passes through unchanged. Column -1 means
		  /// unknown and is omitted.
		  
		  If items = Nil Then Return ""
		  Var lines() As String
		  If Not items.IsArray Then Return items.ToString
		  
		  For i As Integer = 0 To items.Count - 1
		    Var entry As JSONItem = items.ChildAt(i)
		    If entry = Nil Then Continue
		    Var kind As String = If(entry.HasKey("type"), entry.Value("type").StringValue, "")
		    Var isWarning As Boolean = kind.Lowercase.EndsWith("warning")
		    If isWarning <> warningsOnly Then Continue
		    
		    Var text As String = If(kind = "", If(warningsOnly, "Warning", "Error"), kind)
		    If entry.HasKey("message") Then text = text + ": " + entry.Value("message").StringValue
		    If entry.HasKey("line") Then
		      Var line As Integer = entry.Value("line").IntegerValue
		      If line >= 2 Then line = line - 1
		      If line > 0 Then text = text + " (line " + line.ToString + ")"
		    End If
		    If entry.HasKey("column") Then
		      Var column As Integer = entry.Value("column").IntegerValue
		      If column >= 0 Then text = text + " (column " + column.ToString + ")"
		    End If
		    lines.Add(text)
		  Next i
		  
		  Return String.FromArray(lines, EndOfLine)
		End Function
	#tag EndMethod
	#tag Method, Flags = &h21
		Private Function FormatDiagnosticList(list As JSONItem, defaultType As String) As String
		  /// One line per buildError entry: type, message, location and position.
		  
		  If list = Nil Then Return ""
		  Var lines() As String
		  For i As Integer = 0 To list.Count - 1
		    Var err As JSONItem = list.ChildAt(i)
		    If err = Nil Then Continue
		    Var errType As String = If(err.HasKey("type"), err.Value("type").StringValue, defaultType)
		    Var msg As String = If(err.HasKey("message"), err.Value("message").StringValue, "")
		    Var location As String = If(err.HasKey("location"), err.Value("location").StringValue, "")
		    Var position As String = If(err.HasKey("position"), err.Value("position").StringValue, "")
		    Var line As String = errType + ": " + msg
		    If location <> "" Then line = line + " [" + location + "]"
		    If position <> "" And position <> location Then line = line + " (" + position + ")"
		    lines.Add(line)
		  Next i
		  Return String.FromArray(lines, EndOfLine)
		End Function
	#tag EndMethod
	#tag Method, Flags = &h21
		Private Function MergeReply(frames() As JSONItem) As JSONItem
		  /// Folds the parts of one reply into a single envelope so callers keep reading
		  /// response.Value("response") as before. The primary part is chosen by weight: an
		  /// error beats output, output beats a warning, and a warning beats an empty answer -
		  /// an empty reply carries nothing, so it must never displace a warning. Every other part is attached under "xmcp_parts" (their
		  /// "response" values) so a tool can still report, say, the compiler warning that
		  /// accompanied a successful script - see ReplyWarnings.
		  
		  If frames.Count = 0 Then Return Nil
		  If frames.Count = 1 Then Return frames(0)
		  
		  Var primary As Integer = -1
		  Var rank() As String = Array("error", "output", "warning", "empty", "unknown")
		  For r As Integer = 0 To rank.LastIndex
		    For i As Integer = 0 To frames.LastIndex
		      Var kind As String = ReplyKind(frames(i))
		      If kind = rank(r) Then
		        // Among outputs, prefer one that actually says something.
		        If kind = "output" And frames(i).Value("response").Type = Variant.TypeString And _
		          frames(i).Value("response").StringValue = "" Then Continue
		        primary = i
		        Exit For i
		      End If
		    Next i
		    If primary >= 0 Then Exit For r
		  Next r
		  If primary < 0 Then primary = 0
		  
		  Var merged As JSONItem = frames(primary)
		  Var parts As New JSONItem("[]")
		  For i As Integer = 0 To frames.LastIndex
		    If i = primary Then Continue
		    If frames(i).HasKey("response") Then parts.Add(frames(i).Value("response"))
		  Next i
		  If parts.Count > 0 Then merged.Value("xmcp_parts") = parts
		  
		  LogVerbose("Merged " + frames.Count.ToString + " reply parts; primary kind " + ReplyKind(merged) + ".")
		  Return merged
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub AddPending(sock As IPCSocket, tag As String, script As String)
		  /// Parks a socket whose request the IDE accepted but has not answered yet.
		  ///
		  /// The IDE runs scripts on its main thread, so during a build - or behind a modal
		  /// dialog - it answers nothing until it is done, and then answers everything that
		  /// queued up, on the connections the requests arrived on. Closing such a
		  /// connection is what killed the IDE: its later write hits a closed peer, the
		  /// kernel raises SIGPIPE, and the Xojo IDE does not ignore that signal. The system
		  /// log showed "exited due to SIGPIPE | sent by Xojo" five seconds after the build
		  /// finished, with no crash report. So a timed-out socket stays open here until the
		  /// IDE has replied or has gone away; DrainPending does the housekeeping.
		  ///
		  /// The crash is a macOS/Linux one: there the IPCSocket is a Unix domain socket. On
		  /// Windows it is a TCP socket on localhost, where a write into a closed peer merely
		  /// fails. Parking is still right there - a busy IDE accepts the connect into its
		  /// backlog on both platforms, so the request is delivered either way, and refusing
		  /// to stack more behind it is what keeps the message honest.
		  
		  mPendingSockets.Add(sock)
		  mPendingTags.Add(tag)
		  mPendingScripts.Add(script)
		  mPendingSinceUS.Add(System.Microseconds)
		End Sub
	#tag EndMethod
	#tag Method, Flags = &h0
		Function DrainPending() As Integer
		  /// Polls every parked socket and releases the ones the IDE is finished with: it
		  /// wrote a reply (discarded - the caller gave up long ago), or it closed the
		  /// connection (the IDE quit or crashed), or the socket has been parked longer
		  /// than kPendingGiveUpMS. Returns how many are still waiting for the IDE.
		  
		  Var i As Integer = mPendingSockets.LastIndex
		  While i >= 0
		    Var sock As IPCSocket = mPendingSockets(i)
		    Var done As Boolean = False
		    Var reason As String = ""
		    
		    Try
		      sock.Poll
		      // The only thing the IDE ever writes on this connection is the reply, so any
		      // byte at all means the request has been executed.
		      If sock.ReadAll <> "" Then
		        done = True
		        reason = "the IDE answered it (reply discarded)"
		      ElseIf Not sock.IsConnected Then
		        done = True
		        reason = "the IDE closed the connection"
		      ElseIf System.Microseconds - mPendingSinceUS(i) > kPendingGiveUpMS * 1000.0 Then
		        Var giveUpMinutes As Integer = kPendingGiveUpMS / 60000
		        done = True
		        reason = "it was parked for over " + giveUpMinutes.ToString + " minutes"
		      End If
		    Catch e As RuntimeException
		      done = True
		      reason = "polling it failed: " + e.Message
		    End Try
		    
		    If done Then
		      LogVerbose("IDE request " + mPendingTags(i) + ": released, " + reason + ".")
		      Try
		        sock.Close
		      Catch e As RuntimeException
		        // Nothing left to do with it.
		      End Try
		      mPendingSockets.RemoveAt(i)
		      mPendingTags.RemoveAt(i)
		      mPendingScripts.RemoveAt(i)
		      mPendingSinceUS.RemoveAt(i)
		    End If
		    
		    i = i - 1
		  Wend
		  
		  Return mPendingSockets.Count
		End Function
	#tag EndMethod
	#tag Method, Flags = &h21
		Private Function PendingSummary() As String
		  /// One line per parked request: its tag, how long ago it was sent, and the start
		  /// of its script - enough to recognise "that was the build I started".
		  
		  Var lines() As String
		  For i As Integer = 0 To mPendingSockets.LastIndex
		    Var ageS As Integer = Floor((System.Microseconds - mPendingSinceUS(i)) / 1000000.0)
		    Var preview As String = mPendingScripts(i).ReplaceLineEndings(" ").Trim
		    If preview.Length > 80 Then preview = preview.Left(77) + "..."
		    lines.Add("  " + mPendingTags(i) + " (sent " + ageS.ToString + "s ago): " + preview)
		  Next i
		  
		  Return String.FromArray(lines, EndOfLine)
		End Function
	#tag EndMethod

	#tag Property, Flags = &h0
		LastErrorMessage As String
	#tag EndProperty

	#tag Property, Flags = &h1
		Protected mConnected As Boolean
	#tag EndProperty

	#tag Property, Flags = &h1
		Protected mSocketPath As String
	#tag EndProperty

	#tag Property, Flags = &h1
		Protected mTagCounter As Integer
	#tag EndProperty


	#tag Property, Flags = &h21
		Private mParkedThisRequest As Boolean
	#tag EndProperty
	#tag Property, Flags = &h21
		Private mPendingScripts() As String
	#tag EndProperty
	#tag Property, Flags = &h21
		Private mPendingSinceUS() As Double
	#tag EndProperty
	#tag Property, Flags = &h21
		Private mPendingSockets() As IPCSocket
	#tag EndProperty
	#tag Property, Flags = &h21
		Private mPendingTags() As String
	#tag EndProperty
	#tag Constant, Name = kPendingGiveUpMS, Type = Double, Dynamic = False, Default = \"7200000", Scope = Private, Description = 486F77206C6F6E672061207061726B656420736F636B65742069732068656C64206F70656E2077616974696E6720666F72207468652049444520746F20616E737765722C20696E206D696C6C697365636F6E647320283220686F757273292E
	#tag EndConstant
	
	#tag Constant, Name = kConnectTimeoutMS, Type = Double, Dynamic = False, Default = \"1500", Scope = Private
	#tag EndConstant
	
	#tag Constant, Name = kNoListenerPrefix, Type = String, Dynamic = False, Default = \"IPC socket not found", Scope = Private
	#tag EndConstant
	
	#tag Constant, Name = kSplitReplyWindowMS, Type = Double, Dynamic = False, Default = \"250", Scope = Private, Description = 486F77206C6F6E6720746F206B6565702072656164696E6720666F72206D6F726520706172747320616674657220746865206669727374206D61746368696E67207265706C79206672616D652C20696E206D696C6C697365636F6E64732E
	#tag EndConstant
	
	#tag Constant, Name = kSplitWaitForOutputMS, Type = Double, Dynamic = False, Default = \"30000", Scope = Private, Description = 486F77206C6F6E6720746F207761697420666F7220746865207363726970742773207265616C206F7574707574207768656E206F6E6C79206120636F6D70696C6572207761726E696E6720686173206172726976656420736F206661722C20696E206D696C6C697365636F6E64732E
	#tag EndConstant
	
	#tag ViewBehavior
		#tag ViewProperty
			Name="Name"
			Visible=true
			Group="ID"
			InitialValue=""
			Type="String"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Index"
			Visible=true
			Group="ID"
			InitialValue=""
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Super"
			Visible=true
			Group="ID"
			InitialValue=""
			Type="String"
			EditorType=""
		#tag EndViewProperty
	#tag EndViewBehavior
End Class
#tag EndClass
