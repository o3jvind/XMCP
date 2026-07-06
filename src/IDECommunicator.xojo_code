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
		  Var paths() As String
		  paths.Add(mSocketPath)
		  paths.Add(EnvironmentIPCPath())
		  paths.Add("/tmp/XojoIDE")
		  paths.Add("/private/tmp/XojoIDE")
		  
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
		Private Function EnvironmentIPCPath() As String
		  Var envPath As String = System.EnvironmentVariable("XOJO_IPCPATH").Trim
		  If envPath = "" Then Return ""
		  If envPath.IndexOf("/") >= 0 Then Return envPath
		  Return "/tmp/" + envPath
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function FindIPCPath() As String
		  // Honour XOJO_IPCPATH if set, then fall back to standard locations.
		  Var envPath As String = EnvironmentIPCPath()
		  If envPath <> "" Then Return envPath

		  Var paths() As String = Array("/tmp/XojoIDE", "/private/tmp/XojoIDE")
		  For Each p As String In paths
		    Var f As New FolderItem(p, FolderItem.PathModes.Native)
		    If f <> Nil And f.Exists Then Return p
		  Next

		  Return "/tmp/XojoIDE"
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
		  /// Retries up to 3 times with a short pause if the socket is temporarily
		  /// unavailable (e.g. after the Xojo IDE navigates to a new item).

		  LastErrorMessage = ""

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
		      Var responseViaSocket As JSONItem = SendAndReceiveViaIPCSocket(candidatePath, payload, tag, timeoutMS)
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
		    Next candidatePath

		    // All paths failed. If the socket was simply not found (IDE temporarily
		    // closed it after a navigation), wait briefly and retry.
		    Var allNotFound As Boolean = True
		    For Each err As String In socketErrors
		      If Not err.BeginsWith("IPC socket not found") Then
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
		        LastErrorMessage = "No IPCSocket response from Xojo IDE within " + timeoutMS.ToString + "ms."
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
		  ///   - response.response as string → Success(string)
		  ///   - response.response as JSON object with `scriptError` key → Failure
		  ///   - response.response as any other JSON object → Success(json.ToString)
		  /// Tools that need to parse JSON results (e.g. DoCommand "RunApp") should
		  /// keep calling SendAndReceive directly.

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
		    // `scriptError` key (e.g. compile errors in the script we sent).
		    // These must be surfaced as Failure, not stringified as Success.
		    If respJSON.HasKey("scriptError") Then
		      Return MCPKit.ToolResult.Failure("IDE script error: " + respJSON.ToString)
		    End If
		    resp = respJSON.ToString
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
		Private Function SendAndReceiveViaIPCSocket(candidatePath As String, payload As String, tag As String, timeoutMS As Integer) As JSONItem
		  LastErrorMessage = ""
		  
		  Var socketFile As New FolderItem(candidatePath, FolderItem.PathModes.Native)
		  If socketFile = Nil Or Not socketFile.Exists Then
		    LastErrorMessage = "IPC socket not found at: " + candidatePath
		    Return Nil
		  End If
		  
		  Var deadlineUS As Double = System.Microseconds + (timeoutMS * 1000.0)
		  Var sock As New IPCSocket
		  sock.Path = candidatePath
		  
		  Try
		    sock.Connect
		  Catch e As RuntimeException
		    LastErrorMessage = "IPCSocket connect failed for " + candidatePath + ": " + e.Message
		    Return Nil
		  End Try
		  
		  While Not sock.IsConnected And System.Microseconds < deadlineUS
		    sock.Poll
		    App.SleepCurrentThread(5)
		  Wend
		  
		  If Not sock.IsConnected Then
		    sock.Close
		    LastErrorMessage = "IPCSocket connect timeout for " + candidatePath + " within " + timeoutMS.ToString + "ms."
		    Return Nil
		  End If
		  
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
		  
		  While System.Microseconds < deadlineUS
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
		          sock.Close
		          LastErrorMessage = ""
		          Return response
		        End If
		      Catch e As JSONException
		        // Ignore malformed chunks and continue.
		      End Try
		    Wend
		  Wend
		  
		  sock.Close
		  
		  If hadData Then
		    LastErrorMessage = "Received IPC data from " + candidatePath + ", but no matching tag was found for " + tag + "."
		  Else
		    LastErrorMessage = "No IPCSocket response from " + candidatePath + " within " + timeoutMS.ToString + "ms."
		  End If
		  
		  Return Nil
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
