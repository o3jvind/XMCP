#tag Module
Protected Module MCPKit
	#tag Method, Flags = &h1, Description = 52657475726E7320616E206572726F7220746F2074686520636C69656E74206279206F757470757474696E6720746F207374646F75742E2060696460206D617920626520616E20696E7465676572206F72204E696C2E
		Protected Sub Error(id As Variant, errorType As MCPKit.ErrorTypes, errorMessage As String)
		  /// Returns an error to the client by outputting to stdout.
		  /// `id` may be an integer or Nil.
		  
		  Var errorResponse As New JSONItem
		  errorResponse.Value("jsonrpc") = "2.0"
		  // A notification or a parse failure may not have a request id. Calling
		  // `.Type` on a Nil Variant raises NilObjectException in Xojo, which
		  // terminates the stdio MCP server before the client can discover tools.
		  If id = Nil Then
		    errorResponse.Value("id") = Nil
		  Else
		    errorResponse.Value("id") = id
		  End If
		  
		  Var error As New JSONItem
		  error.Value("code") = Integer(errorType)
		  error.Value("message") = errorMessage
		  errorResponse.Value("error") = error
		  
		  Print(errorResponse.ToString)
		  
		  stdout.Flush
		  
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21, Description = 52657475726E7320547275652069662060646020697320612077686F6C65206E756D6265722E
		Private Function IsInteger(d As Double) As Boolean
		  /// Returns True if `d` is a whole number.
		  
		  Return d = Floor(d)
		  
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0, Description = 52657475726E73206120737472696E6720726570726573656E746174696F6E206F66206120746F6F6C20706172616D6574657220747970652E
		Function ToString(Extends type As MCPKit.ToolParameterTypes) As String
		  /// Returns a string representation of a tool parameter type.
		  
		  #Pragma BreakOnExceptions False
		  
		  Select Case type
		  Case MCPKit.ToolParameterTypes.Array_
		    Return "array"
		    
		  Case MCPKit.ToolParameterTypes.Boolean_
		    Return "boolean"
		    
		  Case MCPKit.ToolParameterTypes.Integer_
		    Return "integer"
		    
		  Case MCPKit.ToolParameterTypes.Number_
		    Return "number"
		    
		  Case MCPKit.ToolParameterTypes.Object_
		    Return "object"
		    
		  Case MCPKit.ToolParameterTypes.String_
		    Return "string"
		    
		  Else
		    Raise New InvalidArgumentException("Unknown MCPKit.ToolParameterTypes enumeration.")
		  End Select
		End Function
	#tag EndMethod

	#tag Method, Flags = &h1, Description = 52657475726E732074686520706172616D657465722074797065206F6620746865207061737365642076616C75652E
		Protected Function TypeFromValue(value As Variant) As MCPKit.ToolParameterTypes
		  /// Returns the parameter type of the passed value.
		  
		  If value.IsArray Then Return MCPKit.ToolParameterTypes.Array_

		  If value.Type = Variant.TypeString Then Return MCPKit.ToolParameterTypes.String_

		  If value.Type = Variant.TypeBoolean Then Return MCPKit.ToolParameterTypes.Boolean_

		  If value.IsNumeric Then
		    If MCPKit.IsInteger(value) Then
		      Return MCPKit.ToolParameterTypes.Integer_
		    Else
		      Return MCPKit.ToolParameterTypes.Number_
		    End If
		  End If
		  
		  // Assume it's an object. This includes `null`.
		  Return MCPKit.ToolParameterTypes.Object_
		  
		End Function
	#tag EndMethod


	#tag Note, Name = Credits
		The command line argument parsing classes (Option, OptionException and OptionParser) are very close
		ports of Jeremy Cowgar's option parser:
		
		https://jcowgar.github.io/xojo-option-parser/
		
		The remainder of the MCP implementation was written by Dr Garry Pettet:
		
		https://garrypettet.com
		
		
	#tag EndNote


	#tag Property, Flags = &h1
		Protected VERSION_BUG As Integer = 0
	#tag EndProperty

	#tag Property, Flags = &h1
		Protected VERSION_MAJOR As Integer = 2
	#tag EndProperty

	#tag Property, Flags = &h1
		Protected VERSION_MINOR As Integer = 0
	#tag EndProperty


	#tag Enum, Name = ErrorTypes, Type = Integer, Flags = &h1
		InternalError = -32603
		  InvalidParameters = -32602
		  InvalidRequest = -32600
		  MethodNotFound = -32601
		  ParseError = -32700
		ServerError = -32000
	#tag EndEnum

	#tag Enum, Name = OptionTypes, Flags = &h0
		String
		  Integer
		  Double
		  DateTime
		  Boolean
		  File
		Directory
	#tag EndEnum

	#tag Enum, Name = ToolParameterTypes, Type = Integer, Flags = &h1
		Array_
		  Boolean_
		  Integer_
		  Number_
		  Object_
		String_
	#tag EndEnum


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
	#tag EndViewBehavior
End Module
#tag EndModule
