#tag Class
Protected Class BuildProject
Inherits MCPKit.Tool
	#tag Method, Flags = &h0
		Sub Constructor()
		  Super.Constructor("build_project", "Builds the current Xojo project using the IDE's configured Build Settings. Returns build errors on failure, or a success message on success.")

		  Parameters.Add(New MCPKit.ToolParameter("timeout", MCPKit.ToolParameterTypes.Integer_, _
		  "How long to wait for the build, in milliseconds. Default is 1800000 (30 minutes). Set it generously: giving up does not stop the build, it only means the result is not reported.", _
		  True, CType(kDefaultTimeoutMS, Integer), False))
		  
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Run(args() As MCPKit.ToolArgument) As MCPKit.ToolResult

		  // DoCommand "BuildApp" uses the IDE's configured Build Settings
		  // (BuildMac, BuildWin32, etc.) chosen by the user in the IDE.
		  // On failure it returns a buildError JSON object directly as the
		  // response value (not via Print); on success it returns {}.
		  Var script As String = "DoCommand ""BuildApp""" + EndOfLine + _
		  "Print """""

		  // Builds can take a long time; the wait is configurable and generous by default.
		  If App.IDE = Nil Then
		    Return MCPKit.ToolResult.Failure("Xojo IDE is not connected. Start the IDE and restart XMCP.")
		  End If

		  Var timeoutMS As Integer = CType(kDefaultTimeoutMS, Integer)
		  For Each arg As MCPKit.ToolArgument In args
		    If arg.Name = "timeout" And arg.Value.IntegerValue > 0 Then timeoutMS = arg.Value.IntegerValue
		  Next arg
		  
		  Var response As JSONItem = App.IDE.SendAndReceive(script, timeoutMS)
		  If response = Nil Then
		    If App.IDE.LastErrorMessage <> "" Then
		      Return MCPKit.ToolResult.Failure(App.IDE.LastErrorMessage)
		    End If
		    Var timeoutS As Integer = timeoutMS / 1000
		    Return MCPKit.ToolResult.Failure("No answer from the IDE within " + timeoutS.ToString + "s. " + _
		    "The build is still running in the IDE; wait for it to finish before calling any other tool.")
		  End If

		  If response.HasKey("response") Then
		    Var resp As Variant = response.Value("response")

		    // DoCommand returns a JSON string we printed — parse it.
		    // Happy path: we send `Print ""` after DoCommand "BuildApp",
		    // so a successful build yields an empty string here (not JSON).
		    // Anything else non-JSON is unexpected and should not be reported
		    // as success without surfacing the raw text to the caller.
		    If resp.Type = Variant.TypeString Then
		      Var respStr As String = resp.StringValue
		      If respStr.Trim = "" Then
		        Return MCPKit.ToolResult.Success("Build succeeded.")
		      End If
		      Try
		        Var resultJSON As New JSONItem(respStr)
		        Return ParseDoCommandResult(resultJSON)
		      Catch e As JSONException
		        Return MCPKit.ToolResult.Failure("Unexpected non-JSON response from BuildApp: " + respStr)
		      End Try
		    Else
		      // Already a JSON object in the response envelope.
		      Var respJSON As JSONItem = response.Value("response")
		      Return ParseDoCommandResult(respJSON)
		    End If
		  End If

		  Return MCPKit.ToolResult.Failure("Unexpected response from IDE: " + response.ToString)

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ParseDoCommandResult(resultJSON As JSONItem) As MCPKit.ToolResult
		  /// Parses the JSON returned by DoCommand "BuildApp".
		  /// Success: empty {} -> "Build succeeded."
		  /// Failure: buildError, missingFiles, openErrors or loadError - all of them, via the
		  /// shared classifier in IDECommunicator, so every tool reports them the same way. The
		  /// hand-rolled parse this replaces read buildError.errors only and reported the other
		  /// three shapes as a raw JSON dump under "Build failed:".
		  
		  If resultJSON.Count = 0 Then
		    Return MCPKit.ToolResult.Success("Build succeeded.")
		  End If
		  
		  // Wrap the object the way the IDE delivers it so the classifier can read it.
		  Var envelope As New JSONItem
		  envelope.Value("response") = resultJSON
		  
		  Var diagnostics As String = App.IDE.ReplyDiagnostics(envelope)
		  If diagnostics <> "" Then
		    Var warnings As String = App.IDE.ReplyWarnings(envelope)
		    If warnings <> "" Then diagnostics = diagnostics + EndOfLine + "Warnings:" + EndOfLine + warnings
		    Return MCPKit.ToolResult.Failure(diagnostics)
		  End If
		  
		  // Warnings with no errors: the build completed. Rare from BuildApp, but not a failure.
		  Var warningsOnly As String = App.IDE.ReplyWarnings(envelope)
		  If warningsOnly <> "" Then
		    Return MCPKit.ToolResult.Success("Build succeeded." + EndOfLine + "Warnings:" + EndOfLine + warningsOnly)
		  End If
		  
		  // Unknown JSON structure - return raw for debugging.
		  Return MCPKit.ToolResult.Failure("Build failed: " + resultJSON.ToString)
		  
		End Function
	#tag EndMethod


	#tag Constant, Name = kDefaultTimeoutMS, Type = Double, Dynamic = False, Default = \"1800000", Scope = Private
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
			InitialValue="-2147483648"
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
		#tag ViewProperty
			Name="Left"
			Visible=true
			Group="Position"
			InitialValue="0"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Top"
			Visible=true
			Group="Position"
			InitialValue="0"
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
		#tag ViewProperty
			Name="Description"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="String"
			EditorType="MultiLineEditor"
		#tag EndViewProperty
	#tag EndViewBehavior
End Class
#tag EndClass
