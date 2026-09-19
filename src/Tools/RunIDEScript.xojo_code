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
		  "Timeout in milliseconds to wait for a response. Default is 10000 (10 seconds).", _
		  True, 10000, False))

		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Run(args() As MCPKit.ToolArgument) As MCPKit.ToolResult
		  Var script As String = ""
		  Var timeoutMS As Integer = 10000
		  For Each arg As MCPKit.ToolArgument In args
		    If arg.Name = "script" Then
		      script = arg.Value.StringValue
		    ElseIf arg.Name = "timeout" Then
		      timeoutMS = arg.Value.IntegerValue
		    End If
		  Next arg

		  If script = "" Then
		    Return MCPKit.ToolResult.Failure("The script parameter is required.")
		  End If

		  If App.IDE = Nil Then
		    Return MCPKit.ToolResult.Failure("Xojo IDE is not connected. Start the IDE and restart XMCP.")
		  End If
		  
		  // A script that prints nothing gets no reply at all - measured against the IDE
		  // socket directly: "Print" once yields one frame, twice yields two, and a script
		  // with no Print yields none. Without a reply the request times out and its socket
		  // is parked as though the IDE were busy, which then refuses every later request
		  // until the give-up timer expires - one Print-less script would block the session.
		  //
		  // So append one. The IDE sends a frame per Print rather than only the first, and
		  // MergeReply ranks real output above an empty answer, so a script that does print
		  // still reports its own output; one that does not now answers instead of hanging.
		  Var sent As String = script + EndOfLine + "Print """""
		  
		  Var response As JSONItem = App.IDE.SendAndReceive(sent, timeoutMS)
		  If response = Nil Then
		    If App.IDE.LastErrorMessage <> "" Then
		      Return MCPKit.ToolResult.Failure(App.IDE.LastErrorMessage)
		    End If
		    Return MCPKit.ToolResult.Failure("Timeout waiting for IDE response (" + timeoutMS.ToString + "ms).")
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
		  Var suffix As String = If(warnings = "", "", EndOfLine + EndOfLine + "The IDE also reported warnings about this script (it still ran):" + EndOfLine + warnings)

		  If response.HasKey("response") Then
		    Var resp As Variant = response.Value("response")
		    If resp.Type = Variant.TypeString Then
		      If resp.StringValue = "" Then Return NoOutputResult
		      Return MCPKit.ToolResult.Success(resp.StringValue + suffix)
		    Else
		      Var respJSON As JSONItem = response.Value("response")
		      // An empty object is what the IDE answers when the script printed nothing. It is
		      // not necessarily a failure, but returning a bare "{}" reads like output. So is a
		      // warnings-only object: the script ran, it just printed nothing.
		      If respJSON.Count = 0 Or App.IDE.ReplyKind(response) = "warning" Then Return NoOutputResult
		      Return MCPKit.ToolResult.Success(respJSON.ToString + suffix)
		    End If
		  End If

		  Return MCPKit.ToolResult.Failure("Unexpected response from IDE: " + response.ToString)

		End Function
	#tag EndMethod


	#tag Method, Flags = &h21
		Private Function NoOutputResult() As MCPKit.ToolResult
		  /// The script ran but produced no value.
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
		  "replies; the first meaningful one is reported and the later ones are not returned. " + _
		  "Print once, at the point whose value you want back.")

		End Function
	#tag EndMethod

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
