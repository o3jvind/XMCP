#tag Class
Protected Class DebugControl
Inherits MCPKit.Tool
	#tag Method, Flags = &h0
		Sub Constructor()
		  Super.Constructor("debug_control", "Controls the Xojo debug session. Actions: ""step_over"" (execute current line), ""step_into"" (step into method call), ""step_out"" (step out of current method), ""resume"" (continue running), ""pause"" (pause execution). Requires an active debug session started with run_project.")
		  Parameters.Add(New MCPKit.ToolParameter("action", MCPKit.ToolParameterTypes.String_, _
		  "Debug action to perform: ""step_over"", ""step_into"", ""step_out"", ""resume"", or ""pause"".", _
		  False, "", True))

		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Run(args() As MCPKit.ToolArgument) As MCPKit.ToolResult
		  If App.IDE = Nil Then
		    Return MCPKit.ToolResult.Failure("Xojo IDE is not connected. Start the IDE and restart XMCP.")
		  End If

		  Var action As String = ""
		  For Each arg As MCPKit.ToolArgument In args
		    If arg.Name = "action" Then action = arg.Value.StringValue.Lowercase
		  Next

		  Var command As String
		  Select Case action
		  Case "step_over"
		    command = "StepOver"
		  Case "step_into"
		    command = "StepInto"
		  Case "step_out"
		    command = "StepOut"
		  Case "resume"
		    command = "Resume"
		  Case "pause"
		    command = "Pause"
		  Case Else
		    Return MCPKit.ToolResult.Failure("Unknown action: """ + action + """. Valid actions: step_over, step_into, step_out, resume, pause.")
		  End Select

		  Var script As String = "DoCommand """ + command + """" + EndOfLine + _
		  "Print """""

		  Var result As MCPKit.ToolResult = App.IDE.RunScript(script)
		  If result.IsError Then
		    Return result
		  End If
		  If result.Output.Trim = "" Then
		    Return MCPKit.ToolResult.Success("Debug action """ + action + """ executed.")
		  End If
		  Return result

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
