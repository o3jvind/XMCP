#tag Class
Protected Class AnalyzeProject
Inherits MCPKit.Tool
	#tag Method, Flags = &h0
		Sub Constructor()
		  Super.Constructor("analyze_project", "Analyzes the current Xojo project for compile errors and warnings without building. Reports unused variables, type mismatches, deprecated API usage, and other issues. Pass scope=""item"" to analyze only the currently selected item (faster); default is ""project"" to analyze everything.")
		  Parameters.Add(New MCPKit.ToolParameter("scope", MCPKit.ToolParameterTypes.String_, _
		  "Scope to analyze: ""project"" (default) or ""item"" (currently selected item only).", _
		  True, "project", False))
		  
		  Parameters.Add(New MCPKit.ToolParameter("timeout", MCPKit.ToolParameterTypes.Integer_, _
		  "How long to wait for the analysis, in milliseconds. Default is 300000 (5 minutes); a large project can need more. 0 or a negative value means this default, not 'no limit'. If it takes longer, it carries on in the IDE and this request is left waiting for the answer: further requests are turned down until the IDE answers, and the MCP client must not be quit or restarted meanwhile - on macOS and Linux the IDE crashes if it answers after that.", _
		  True, CType(kDefaultTimeoutMS, Integer), False))

		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Run(args() As MCPKit.ToolArgument) As MCPKit.ToolResult
		  If App.IDE = Nil Then
		    Return MCPKit.ToolResult.Failure("Xojo IDE is not connected. Start the IDE and restart XMCP.")
		  End If

		  Var scope As String = "project"
		  Var timeoutMS As Integer = TimeoutArg(args, CType(kDefaultTimeoutMS, Integer))
		  For Each arg As MCPKit.ToolArgument In args
		    If arg.Name = "scope" Then scope = arg.Value.StringValue.Lowercase
		  Next

		  Var command As String
		  If scope = "item" Then
		    command = "CheckItemErrors"
		  Else
		    command = "CheckProjectErrors"
		  End If

		  Var script As String = "DoCommand """ + command + """" + EndOfLine + _
		  "Print """""

		  Var response As JSONItem = App.IDE.SendAndReceive(script, timeoutMS)
		  If response = Nil Then
		    If App.IDE.LastErrorMessage <> "" Then
		      Return MCPKit.ToolResult.Failure(App.IDE.LastErrorMessage)
		    End If
		    Var timeoutS As Integer = timeoutMS / 1000
		    Return MCPKit.ToolResult.Failure("No answer from the IDE within " + timeoutS.ToString + "s. " + _
		    "The analysis is still running in the IDE; wait for it to finish before calling any other tool.")
		  End If

		  If response.HasKey("response") Then
		    Var resp As Variant = response.Value("response")

		    If resp.Type = Variant.TypeString Then
		      Var respStr As String = resp.StringValue
		      If respStr.Trim = "" Then
		        Return MCPKit.ToolResult.Success("No errors or warnings found.")
		      End If
		      Try
		        Var resultJSON As New JSONItem(respStr)
		        Return ParseAnalyzeResult(resultJSON)
		      Catch e As JSONException
		        Return MCPKit.ToolResult.Failure("Unexpected non-JSON response: " + respStr)
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
		      Return ParseAnalyzeResult(respJSON)
		    End If
		  End If

		  Return MCPKit.ToolResult.Failure("Unexpected response from IDE: " + response.ToString)

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ParseAnalyzeResult(resultJSON As JSONItem) As MCPKit.ToolResult
		  /// Turns CheckProjectErrors/CheckItemErrors output into a result.
		  ///
		  /// The buildError lists are formatted by IDECommunicator.FormatDiagnosticList, the same
		  /// routine build_project and run_project report through. It used to be hand-rolled here,
		  /// twice - once for errors and once for warnings - and the copies had already drifted:
		  /// the warning loop ignored an entry's own "type" field and always wrote "Warning".
		  ///
		  /// The heading stays this tool's own. "Build errors" is ReplyDiagnostics' wording and
		  /// would be a misnomer for a tool that deliberately does not build.
		  ///
		  /// Every other shape the IDE can answer with - missingFiles, openErrors, loadError,
		  /// scriptError - goes to ReplyDiagnostics. Those used to fall through to a raw JSON dump
		  /// under "Unexpected response", which is the same gap that was fixed in build_project.
		  
		  If resultJSON = Nil Then Return MCPKit.ToolResult.Success("No errors or warnings found.")
		  
		  // Wrapped the way the IDE delivers a reply, so the shared classifier can judge it - the same
		  // test for "nothing to report" as build_project's, which also covers a buildError whose lists
		  // are both empty.
		  Var envelope As New JSONItem
		  envelope.Value("response") = resultJSON
		  If App.IDE.ReplyKind(envelope) = "empty" Then
		    Return MCPKit.ToolResult.Success("No errors or warnings found.")
		  End If
		  
		  // This tool's own formatting is used only for the build result shape the IDE sends
		  // (BuildErrorIsKnownShape - the same test the classifier uses); any other shape goes to the
		  // shared classifier below, which reports it as it arrived. So does one whose entries this
		  // cannot read: that throws partway, and the Catch falls through to the same place. HasKey
		  // is inside the Try too - the reply need not be an object with keys at all.
		  Try
		    If resultJSON.HasKey("buildError") And App.IDE.BuildErrorIsKnownShape(resultJSON.Value("buildError")) Then
		      Var be As JSONItem = resultJSON.Value("buildError")
		      Var lines() As String
		      Var errorCount As Integer = 0
		      Var warningCount As Integer = 0
		      
		      If be <> Nil And be.HasKey("errors") Then
		        Var errs As JSONItem = be.Value("errors")
		        If errs <> Nil And errs.Count > 0 Then
		          errorCount = errs.Count
		          lines.Add(App.IDE.FormatDiagnosticList(errs, "Error"))
		        End If
		      End If
		      
		      If be <> Nil And be.HasKey("warnings") Then
		        Var warns As JSONItem = be.Value("warnings")
		        If warns <> Nil And warns.Count > 0 Then
		          warningCount = warns.Count
		          lines.Add(App.IDE.FormatDiagnosticList(warns, "Warning", True))
		        End If
		      End If
		      
		      If lines.Count = 0 Then
		        Return MCPKit.ToolResult.Success("No errors or warnings found.")
		      End If
		      
		      Var summary As String = ""
		      If errorCount > 0 Then summary = errorCount.ToString + " error(s)"
		      If warningCount > 0 Then
		        If summary <> "" Then summary = summary + ", "
		        summary = summary + warningCount.ToString + " warning(s)"
		      End If
		      
		      Var result As String = "Analysis results (" + summary + "):" + EndOfLine + String.FromArray(lines, EndOfLine)
		      
		      If errorCount > 0 Then
		        Return MCPKit.ToolResult.Failure(result)
		      Else
		        Return MCPKit.ToolResult.Success(result)
		      End If
		    End If
		  Catch e As RuntimeException
		  End Try
		  
		  // Not a build result of the known shape, or one that could not be read: report whatever
		  // the shared classifier recognises.
		  
		  Var diagnostics As String = App.IDE.ReplyDiagnostics(envelope)
		  If diagnostics <> "" Then Return MCPKit.ToolResult.Failure(diagnostics)
		  
		  Var warnings As String = App.IDE.ReplyWarnings(envelope)
		  If warnings <> "" Then
		    Return MCPKit.ToolResult.Success("Analysis results:" + EndOfLine + warnings)
		  End If
		  
		  Return MCPKit.ToolResult.Failure("Unexpected response: " + resultJSON.ToString)
		  
		End Function
	#tag EndMethod

	#tag Constant, Name = kDefaultTimeoutMS, Type = Double, Dynamic = False, Default = \"300000", Scope = Private, Description = 486F77206C6F6E6720746F207761697420666F722074686520616E616C797369732C20696E206D696C6C697365636F6E64732E
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
