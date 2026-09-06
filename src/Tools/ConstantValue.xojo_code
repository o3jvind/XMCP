#tag Class
Protected Class ConstantValue
Inherits MCPKit.Tool
	#tag Method, Flags = &h0
		Sub Constructor()
		  Super.Constructor("constant_value", "Gets or sets the value of a project constant in the Xojo IDE. The constant must already exist in the project.")

		  Parameters.Add(New MCPKit.ToolParameter("name", MCPKit.ToolParameterTypes.String_, _
		  "The fully-qualified constant name (e.g. 'App.kVersion'). A bare name (e.g. 'kVersion') silently fails in the Xojo IDE scripting API — always qualify with the containing module or class.", _
		  False, "", True))

		  Parameters.Add(New MCPKit.ToolParameter("value", MCPKit.ToolParameterTypes.String_, _
		  "If provided, sets the constant to this value. If omitted, returns the current value.", _
		  True, "", False))

		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Run(args() As MCPKit.ToolArgument) As MCPKit.ToolResult
		  Var name As String = ""
		  Var value As String = ""
		  Var hasValue As Boolean = False

		  For Each arg As MCPKit.ToolArgument In args
		    If arg.Name = "name" Then
		      name = arg.Value.StringValue
		    ElseIf arg.Name = "value" Then
		      value = arg.Value.StringValue
		      hasValue = True
		    End If
		  Next arg

		  If name = "" Then
		    Return MCPKit.ToolResult.Failure("Parameter 'name' is required.")
		  End If

		  If App.IDE = Nil Then
		    Return MCPKit.ToolResult.Failure("Xojo IDE is not connected. Start the IDE and restart XMCP.")
		  End If

		  Var script As String
		  If hasValue Then
		    ' Xojo's IDE-scripting ConstantValue() assignment never raises an error —
		    ' it silently no-ops for an unknown or unqualified name. Read the value
		    ' back and compare so a no-op assignment is reported as a failure
		    ' instead of a false "OK".
		    ' Build the value via a String variable (not inline between literal
		    ' quotes) so a value containing a newline doesn't break the script
		    ' across lines.
		    script = BuildStringVariableScript("__value", value) + EndOfLine + _
		    "ConstantValue(""" + name.ReplaceAll("""", """""") + """) = __value" + EndOfLine + _
		    "If ConstantValue(""" + name.ReplaceAll("""", """""") + """) = __value Then" + EndOfLine + _
		    "  Print ""OK""" + EndOfLine + _
		    "Else" + EndOfLine + _
		    "  Print ""ERROR: Constant '" + name.ReplaceAll("""", """""") + "' was not found or the value did not take effect. Use the fully-qualified form Module.ConstantName.""" + EndOfLine + _
		    "End If"
		  Else
		    script = "Print ConstantValue(""" + name.ReplaceAll("""", """""") + """)"
		  End If

		  Return App.IDE.RunScript(script)

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
