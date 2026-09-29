#tag Class
Protected Class RunIDEScript
Inherits MCPKit.Tool
	#tag Method, Flags = &h0
		Sub Constructor()
		  Super.Constructor("run_ide_script", "Executes an arbitrary Xojo IDE script. Use Print to return values. This is an escape hatch for any IDE scripting command not covered by other tools.")

		  Parameters.Add(New MCPKit.ToolParameter("script", MCPKit.ToolParameterTypes.String_, _
		  "The IDE script code to execute. Use XojoScript syntax with IDE scripting commands. " + _
		  "Use Print to return output values.", _
		  False, "", True))

		  Parameters.Add(New MCPKit.ToolParameter("timeout", MCPKit.ToolParameterTypes.Integer_, _
		  "How long to wait for the script to answer, in milliseconds. Default is 10000 (10 seconds). 0 or a negative value means this default, not 'no limit'. If the script takes longer - or opens a dialog that waits for a click - it carries on in the IDE and this request is left waiting for the answer: further requests are turned down until the IDE answers, and the MCP client must not be quit or restarted meanwhile - on macOS and Linux the IDE crashes if it answers after that.", _
		  True, CType(kDefaultTimeoutMS, Integer), False))

		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Run(args() As MCPKit.ToolArgument) As MCPKit.ToolResult
		  Var script As String = ""
		  Var timeoutMS As Integer = TimeoutArg(args, CType(kDefaultTimeoutMS, Integer))
		  For Each arg As MCPKit.ToolArgument In args
		    If arg.Name = "script" Then
		      script = arg.Value.StringValue
		    End If
		  Next arg

		  // Trimmed: a script of nothing but whitespace is as empty as "". It used to pass this
		  // guard and then defeat the sentinel too, because the sentinel was skipped when the
		  // trimmed script was empty - so it reached the IDE with no Print, was never answered,
		  // and parked its socket for the full give-up window.
		  If script.Trim = "" Then
		    Return MCPKit.ToolResult.Failure("The script parameter is required.")
		  End If

		  If App.IDE = Nil Then
		    Return MCPKit.ToolResult.Failure("Xojo IDE is not connected. Start the IDE and restart XMCP.")
		  End If
		  
		  Var response As JSONItem = App.IDE.SendAndReceive(script, timeoutMS)
		  If response = Nil Then
		    If App.IDE.LastErrorMessage <> "" Then
		      Return MCPKit.ToolResult.Failure(App.IDE.LastErrorMessage)
		    End If
		    // Worded like RunScript's fallback, so the same situation reads the same in every tool.
		    Var timeoutS As Integer = timeoutMS / 1000
		    Return MCPKit.ToolResult.Failure("No answer from the IDE within " + timeoutS.ToString + "s.")
		  End If

		  // Errors first. ReplyDiagnostics reads every error shape the IDE sends and already
		  // separates scriptCompilerWarning entries (the script ran) from real errors, and
		  // corrects the line numbers, which the IDE reports one too high because it wraps the
		  // script in a line of boilerplate before compiling it.
		  Var diagnostics As String = App.IDE.ReplyDiagnostics(response)
		  If diagnostics <> "" Then
		    Return MCPKit.ToolResult.Failure(diagnostics)
		  End If

		  // A compiler warning about the script arrives as a separate reply part; report it
		  // with the output rather than instead of it.
		  Var warnings As String = App.IDE.ReplyWarnings(response)
		  Var suffix As String = If(warnings = "", "", EndOfLine + EndOfLine + "The IDE also reported warnings (the script still ran):" + EndOfLine + warnings)

		  If response.HasKey("response") Then
		    Var resp As Variant = response.Value("response")
		    If resp.Type = Variant.TypeString Then
		      // Exact, not trimmed, unlike build_project, run_project and analyze_project - and
		      // that difference is deliberate. Those three trim a protocol reply: whether a build
		      // printed an error object or nothing, where whitespace means nothing. Here the value
		      // is whatever the caller's script printed. Rule: trim when judging a protocol reply,
		      // never when handling data. (Whitespace-only output never arrives anyway - the IDE
		      // collapses a Print of only spaces into an empty reply - so this is about the rule,
		      // not a case that currently occurs.)
		      If resp.StringValue = "" Then Return NoOutputResult(suffix)
		      Return MCPKit.ToolResult.Success(resp.StringValue + suffix)
		    Else
		      // An empty object is what the IDE answers when the script printed nothing. It is
		      // not necessarily a failure, but returning a bare "{}" reads like output. So is a
		      // warnings-only object: the script ran, it just printed nothing. The classifier
		      // decides both, as it does in every other tool - an object can be "empty" without
		      // having no keys, such as a build result whose lists are both empty.
		      Var kind As String = App.IDE.ReplyKind(response)
		      If kind = "empty" Or kind = "warning" Then Return NoOutputResult(suffix)
		      // Not every value that is not a string is an object: the classifier counts a number
		      // or a boolean as output too, and converting one to a JSONItem throws.
		      Var text As String
		      Try
		        Var respJSON As JSONItem = response.Value("response")
		        text = respJSON.ToString
		      Catch e As RuntimeException
		        text = resp.StringValue
		      End Try
		      // A JSON null reads as nothing at all - "no value", the same as an empty string.
		      If text = "" Then Return NoOutputResult(suffix)
		      Return MCPKit.ToolResult.Success(text + suffix)
		    End If
		  End If

		  Return MCPKit.ToolResult.Failure("Unexpected response from IDE: " + response.ToString)

		End Function
	#tag EndMethod


	#tag Method, Flags = &h21
		Private Function NoOutputResult(suffix As String = "") As MCPKit.ToolResult
		  /// The script ran but produced no value. Any compiler warnings the script raised are
		  /// passed in as suffix: a script that prints nothing still reports them, otherwise a
		  /// warning would be heard only when the script happened to print something too.
		  ///
		  /// Measured against the IDE socket on 2026r2.1: the IDE sends one reply frame per
		  /// Print, not just the first - two Prints answer twice, under the same tag. A script
		  /// with no Print at all answers not at all, which is why one is appended before
		  /// sending. Print "" answers with an empty object, so that is what "no value" looks
		  /// like on the wire.
		  
		  Return MCPKit.ToolResult.Success("The script ran but produced no value." + EndOfLine + _
		  EndOfLine + _
		  "The usual reason is that the script has no Print, so it returned nothing to print. " + _
		  "Some commands also have no value to give - PropertyValue returns nothing for an item " + _
		  "it does not support, since it only reads framework properties of items such as App " + _
		  "or a Window. Neither case means the script failed: verify the effect in a separate " + _
		  "call. Note that the IDE answers once per Print, so several Prints send several " + _
		  "replies; XMCP merges them and reports the most significant part - an error outranks " + _
		  "printed output, which outranks a warnings-only reply - so a later Print's value " + _
		  "can be the one you see. " + _
		  "Print once, at the point whose value you want back." + suffix)

		End Function
	#tag EndMethod

	#tag Constant, Name = kDefaultTimeoutMS, Type = Double, Dynamic = False, Default = \"10000", Scope = Private
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
