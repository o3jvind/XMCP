#tag Class
Protected Class RunProject
Inherits MCPKit.Tool
	#tag Method, Flags = &h0
		Sub Constructor()
		  Super.Constructor("run_project", "Runs the current Xojo project in debug mode.")

		  Parameters.Add(New MCPKit.ToolParameter("timeout", MCPKit.ToolParameterTypes.Integer_, _
		  "How long to wait for the debug build to compile and start, in milliseconds. Default is 1800000 (30 minutes). 0 or a negative value means this default, not 'no limit'. If it takes longer, it carries on in the IDE and this request is left waiting for the answer: further requests are turned down until the IDE answers, and the MCP client must not be quit or restarted meanwhile - on macOS and Linux the IDE crashes if it answers after that. So set it generously.", _
		  True, CType(kDefaultTimeoutMS, Integer), False))
		  
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Run(args() As MCPKit.ToolArgument) As MCPKit.ToolResult

		  // DoCommand "RunApp" returns a buildError JSON object on failure,
		  // or {} on success. The IDE returns it directly as the response value —
		  // not via Print — so we just call DoCommand and let the response come back.
		  Var script As String = "DoCommand ""RunApp""" + EndOfLine + _
		  "Print """""

		  If App.IDE = Nil Then
		    Return MCPKit.ToolResult.Failure("Xojo IDE is not connected. Start the IDE and restart XMCP.")
		  End If

		  Var timeoutMS As Integer = TimeoutArg(args, CType(kDefaultTimeoutMS, Integer))
		  Var response As JSONItem = App.IDE.SendAndReceive(script, timeoutMS)
		  If response = Nil Then
		    If App.IDE.LastErrorMessage <> "" Then
		      Return MCPKit.ToolResult.Failure(App.IDE.LastErrorMessage)
		    End If
		    Var timeoutS As Integer = timeoutMS / 1000
		    Return MCPKit.ToolResult.Failure("No answer from the IDE within " + timeoutS.ToString + "s. " + _
		    "The debug build is still running in the IDE; wait for it to finish before calling any other tool.")
		  End If

		  If response.HasKey("response") Then
		    Var resp As Variant = response.Value("response")

		    // DoCommand "RunApp" answers with a JSON object as the response value: {} on success,
		    // a buildError (or another of the shapes ParseDoCommandResult reads) otherwise. The
		    // `Print ""` that follows it also answers {}, not an empty string. A string arrives
		    // only if the IDE ever sends the result as text, so it is read as JSON too - and text
		    // that is not JSON is reported as it is rather than as success.
		    If resp.Type = Variant.TypeString Then
		      Var respStr As String = resp.StringValue
		      If respStr.Trim = "" Then
		        Return MCPKit.ToolResult.Success("Project launched in debug mode.")
		      End If
		      Try
		        Var resultJSON As New JSONItem(respStr)
		        Return ParseDoCommandResult(resultJSON)
		      Catch e As JSONException
		        Return MCPKit.ToolResult.Failure("Unexpected non-JSON response from RunApp: " + respStr)
		      End Try
		    Else
		      // Not every value that is not a string is an object - the classifier counts a number or
		      // a boolean as output - and converting one to a JSONItem throws. The same guard as
		      // run_ide_script's.
		      Var respJSON As JSONItem
		      Try
		        respJSON = response.Value("response")
		      Catch e As RuntimeException
		      End Try
		      If respJSON = Nil Then Return MCPKit.ToolResult.Failure("Unexpected response from IDE: " + response.ToString)
		      Return ParseDoCommandResult(respJSON)
		    End If
		  End If

		  Return MCPKit.ToolResult.Failure("Unexpected response from IDE: " + response.ToString)

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ParseDoCommandResult(resultJSON As JSONItem) As MCPKit.ToolResult
		  /// Parses the JSON returned by DoCommand "RunApp" / "BuildApp".
		  /// Success: nothing to report ({}, or a buildError with empty lists) → "Project launched in debug mode."
		  /// Failure: {"buildError": {"errors": [...]}} → formatted error list.


		  // buildError, missingFiles, openErrors, loadError - formatted by the shared
		  // classifier in IDECommunicator so every tool reports them the same way.
		  Var envelope As New JSONItem
		  envelope.Value("response") = resultJSON
		  
		  // Nothing to report is success: {} as well as a buildError whose lists are empty. The
		  // classifier decides it, so this tool and analyze_project cannot disagree about it.
		  If App.IDE.ReplyKind(envelope) = "empty" Then
		    Return MCPKit.ToolResult.Success("Project launched in debug mode.")
		  End If
		  Var diagnostics As String = App.IDE.ReplyDiagnostics(envelope)
		  If diagnostics <> "" Then
		    Var warnings As String = App.IDE.ReplyWarnings(envelope)
		    If warnings <> "" Then diagnostics = diagnostics + EndOfLine + "Warnings:" + EndOfLine + warnings
		    Return MCPKit.ToolResult.Failure(diagnostics)
		  End If

		  // Warnings only: the debug build compiled and is running.
		  Var warningsOnly As String = App.IDE.ReplyWarnings(envelope)
		  If warningsOnly <> "" Then
		    Return MCPKit.ToolResult.Success("Project launched in debug mode." + EndOfLine + "Warnings:" + EndOfLine + warningsOnly)
		  End If

		  // Unknown JSON structure: return raw for debugging.
		  Return MCPKit.ToolResult.Failure("Run failed: " + resultJSON.ToString)

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
