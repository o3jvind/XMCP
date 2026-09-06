#tag Class
Protected Class GetItemDescription
Inherits MCPKit.Tool
	#tag Method, Flags = &h0
		Sub Constructor()
		  Super.Constructor("get_item_description", "Gets or sets the description of the currently selected project item (method, property, event, etc.) in the Xojo IDE. Pass a value to set the description, or omit it to read the current description.")

		  Parameters.Add(New MCPKit.ToolParameter("location", MCPKit.ToolParameterTypes.String_, _
		  "Optional dot-separated path to navigate to before reading/writing (e.g. 'App.MyMethod'). If empty, uses current location.", _
		  True, "", False))

		  Parameters.Add(New MCPKit.ToolParameter("value", MCPKit.ToolParameterTypes.String_, _
		  "If provided, sets the description to this value. If omitted, returns the current description.", _
		  True, "", False))

		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Run(args() As MCPKit.ToolArgument) As MCPKit.ToolResult
		  Var location As String = ""
		  Var value As String = ""
		  Var hasValue As Boolean = False

		  For Each arg As MCPKit.ToolArgument In args
		    If arg.Name = "location" Then
		      location = arg.Value.StringValue
		    ElseIf arg.Name = "value" Then
		      value = arg.Value.StringValue
		      hasValue = True
		    End If
		  Next arg

		  If App.IDE = Nil Then
		    Return MCPKit.ToolResult.Failure("Xojo IDE is not connected. Start the IDE and restart XMCP.")
		  End If

		  Var action As String
		  If hasValue Then
		    ' Build the value via a String variable (not inline between literal
		    ' quotes) so a value containing a newline doesn't break the script
		    ' across lines.
		    action = BuildStringVariableScript("__value", value) + EndOfLine + _
		    "ItemDescription = __value" + EndOfLine + _
		    "Print ""OK"""
		  Else
		    action = "Print ItemDescription"
		  End If

		  Var script As String
		  If location <> "" Then
		    script = "If Not SelectProjectItem(""" + location.ReplaceAll("""", """""") + """) Then" + EndOfLine + _
		    "  Print ""ERROR: Could not navigate to: " + location.ReplaceAll("""", """""") + """" + EndOfLine + _
		    "Else" + EndOfLine + _
		    "  " + action + EndOfLine + _
		    "End If"
		  Else
		    script = action
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
