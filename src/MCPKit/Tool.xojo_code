#tag Class
Protected Class Tool
	#tag Method, Flags = &h1, Description = 52657475726E732054727565206966207468652070617373656420706172616D6574657220616E6420617267756D656E742061726520636F6D70617469626C652E
		Protected Function Compatible(param As MCPKit.ToolParameter, arg As MCPKit.ToolArgument) As Boolean
		  /// Returns True if the passed parameter and argument are compatible.
		  
		  // Names must match.
		  If param.Name <> arg.Name Then Return False
		  
		  // Easy if both types match.
		  If param.Type = arg.Type Then Return True
		  
		  // All integers are numbers but not all numbers are integers...
		  If param.Type = MCPKit.ToolParameterTypes.Integer_ And arg.Type = MCPKit.ToolParameterTypes.Number_ Then
		    Return False
		  End If
		  If param.Type = MCPKit.ToolParameterTypes.Number_ And arg.Type = MCPKit.ToolParameterTypes.Integer_ Then
		    Return True
		  End If
		  
		  // Not compatible.
		  Return False
		  
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub Constructor(name As String, description As String)
		  #Pragma BreakOnExceptions False
		  
		  If name = "" Then
		    Raise New InvalidArgumentException("A tool cannot have an empty name.")
		  Else
		    Self.Name = name
		  End If
		  
		  If description = "" Then
		    Raise New InvalidArgumentException("You must provide a description for a tool.")
		  Else
		    Self.Description = description
		  End If
		  
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 52756E73207468697320746F6F6C20616E642072657475726E732074686520726573756C742E205573652060546F6F6C526573756C742E53756363657373286F757470757429602C2060546F6F6C526573756C742E4661696C757265286572726F724D65737361676529602C206F7220746865206064697265637420636F6E7374727563746F722E
		Function Run(args() As MCPKit.ToolArgument) As MCPKit.ToolResult
		  /// Runs this tool and returns the result.
		  /// Use `ToolResult.Success(output)`, `ToolResult.Failure(errorMessage)`, or the direct constructor.
		  ///
		  /// Example:
		  ///   Return MCPKit.ToolResult.Success("Operation completed")
		  ///   Return MCPKit.ToolResult.Failure("Could not access resource")
		  
		  #Pragma Unused args
		  
		  Raise New UnsupportedOperationException("The `Run()` method should be overridden by subclasses.")
		  
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 52657475726E732061204A534F4E20726570726573656E746174696F6E206F66207468697320746F6F6C2E
		Function ToJSONItem() As JSONItem
		  /// Returns a JSON representation of this tool.
		  
		  // Create the `web_search` tool.
		  Var tool As New JSONItem
		  tool.Value("name") = Name
		  tool.Value("description") = Description
		  
		  // Create the input schema.
		  Var inputSchema As New JSONItem
		  inputSchema.Value("type") = "object"
		  
		  // Required properties.
		  Var requiredProperties As New JSONItem("[]")
		  
		  // Define properties.
		  Var jsonProperties As New JSONItem
		  For Each param As MCPKit.ToolParameter In Parameters
		    If param.Required Then requiredProperties.Add(param.Name)
		    jsonProperties.Value(param.Name) = param.ToJSONItem
		  Next param
		  
		  // Add the property definitions to the schema.
		  inputSchema.Value("properties") = jsonProperties
		  
		  // Add the required properties to the schema.
		  inputSchema.Value("required") = requiredProperties
		  
		  tool.Value("inputSchema") = inputSchema
		  
		  Return tool
		  
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 56616C69646174657320746861742074686520617267756D656E747320706173736564206D617463682077686174207468697320746F6F6C20657870656374732E2049662076616C6964207468656E20616E20656D70747920737472696E672069732072657475726E65642C206F74686572776973652077652072657475726E20746865206572726F72206D6573736167652E
		Function ValidateArguments(arguments() As MCPKit.ToolArgument) As String
		  /// Validates that the arguments passed match what this tool expects.
		  /// If valid then an empty string is returned, otherwise we return the error message.
		  
		  // Easy exit?
		  If Parameters.Count = 0 And arguments.Count = 0 Then Return ""
		  
		  // How many required and optional properties are there?
		  Var requiredParams(), optionalParams() As MCPKit.ToolParameter
		  For Each param As MCPKit.ToolParameter In Parameters
		    If param.Required Then
		      requiredParams.Add(param)
		    Else
		      optionalParams.Add(param)
		    End If
		  Next param
		  
		  // Clone the arguments array because we'll do some popping...
		  Var tmp() As MCPKit.ToolArgument
		  For Each arg As MCPKit.ToolArgument In arguments
		    tmp.Add(arg)
		  Next arg
		  
		  // Check required properties.
		  For i As Integer = requiredParams.LastIndex DownTo 0
		    Var param As MCPKit.ToolParameter = requiredParams(i)
		    For j As Integer = tmp.LastIndex DownTo 0
		      Var arg As MCPKit.ToolArgument = tmp(j)
		      
		      If param.Name = arg.Name And Not Compatible(param, arg) Then
		        Return "Wrong parameter type for parameter named `" + param.Name + "`. Expected " + _
		        param.Type.ToString + " but received " + arg.Type.ToString + "."
		      End If
		      
		      If Compatible(param, arg) Then
		        tmp.RemoveAt(j)
		        requiredParams.RemoveAt(i)
		        Continue For i
		      End If
		    Next j
		  Next i
		  
		  If requiredParams.Count = 1 Then
		    Return "Missing the required `" + requiredParams(0).Name + "` parameter."
		  ElseIf requiredParams.Count > 0 Then
		    Var missing() As String
		    For Each rp As MCPKit.ToolParameter In requiredParams
		      missing.Add(rp.Name)
		    Next rp
		    Return "Missing multiple required parameters (" + String.FromArray(missing, ", ") + ")."
		  End If
		  
		  // Check optional properties.
		  For i As Integer = optionalParams.LastIndex DownTo 0
		    Var param As MCPKit.ToolParameter = optionalParams(i)
		    For j As Integer = tmp.LastIndex DownTo 0
		      Var arg As MCPKit.ToolArgument = tmp(j)
		      
		      If param.Name = arg.Name And Not Compatible(param, arg) Then
		        Return "Wrong parameter type for parameter named `" + param.Name + "`. Expected " + _
		        param.Type.ToString + " but received " + arg.Type.ToString + "."
		      End If
		      
		      If Compatible(param, arg) Then
		        tmp.RemoveAt(j)
		        optionalParams.RemoveAt(i)
		        Continue For i
		      End If
		    Next j
		  Next i
		  
		  // Make sure we haven't been passed too many parameters.
		  If tmp.Count > 0 Then
		    Var extra() As String
		    For Each arg As MCPKit.ToolArgument In tmp
		      extra.Add("`" + arg.Name + "`")
		    Next arg
		    Return "Unexpected parameters (" + String.FromArray(extra, ", ") + ") passed to `" + Self.Name + "` tool."
		  End If
		  
		  // All good.
		  Return ""
		  
		End Function
	#tag EndMethod


	#tag Method, Flags = &h1
		Protected Function BuildStringVariableScript(variableName As String, value As String) As String
		  // Split on CRLF/CR/LF individually (not just EndOfLine, which is LF-only
		  // on macOS) so a raw CR embedded in `value` (e.g. from "a\r\nb" or "a\rb")
		  // never ends up as a literal control byte inside a script string literal,
		  // which would break the IDE script's syntax. Each segment is emitted as
		  // its own quoted piece, joined by the exact separator it had — Chr(13),
		  // Chr(10), or Chr(13)+Chr(10) as literal Chr() calls, not EndOfLine —
		  // so CR/LF/CRLF are all preserved exactly as they were in the value.
		  Var segments() As String
		  Var separators() As String
		  Var current As String = ""
		  Var i As Integer = 0
		  While i < value.Length
		    Var ch As String = value.Middle(i, 1)
		    If ch = Chr(13) And value.Middle(i + 1, 1) = Chr(10) Then
		      segments.Add(current)
		      separators.Add("Chr(13) + Chr(10)")
		      current = ""
		      i = i + 2
		    ElseIf ch = Chr(13) Or ch = Chr(10) Then
		      segments.Add(current)
		      separators.Add("Chr(" + Str(ch.Asc) + ")")
		      current = ""
		      i = i + 1
		    Else
		      current = current + ch
		      i = i + 1
		    End If
		  Wend
		  segments.Add(current)

		  Var scriptLines() As String
		  scriptLines.Add("Dim " + variableName + " As String = """"")
		  For j As Integer = 0 To segments.LastIndex
		    Var sep As String = If(j = 0, "", " + " + separators(j - 1))
		    scriptLines.Add(variableName + " = " + variableName + sep + " + """ + segments(j).ReplaceAll("""", """""") + """")
		  Next j

		  Return String.FromArray(scriptLines, EndOfLine)

		End Function
	#tag EndMethod


	#tag Property, Flags = &h0, Description = 41206465736372697074696F6E206F662077686174207468697320746F6F6C20646F65732E
		Description As String
	#tag EndProperty

	#tag Property, Flags = &h0, Description = 546865206E616D65206F66207468697320746F6F6C2E
		Name As String
	#tag EndProperty

	#tag Property, Flags = &h1, Description = 5468697320746F6F6C27732070726F706572746965732E
		Protected Parameters() As MCPKit.ToolParameter
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
			Name="Name"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="String"
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
