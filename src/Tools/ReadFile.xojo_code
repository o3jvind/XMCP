#tag Class
Protected Class ReadFile
Inherits MCPKit.Tool
	#tag Method, Flags = &h0
		Sub Constructor()
		  Super.Constructor("read_file", "Reads the full text content of a file from disk and returns it as a string. Use this to read Xojo source files (.xojo_code, .xojo_window, .xojo_project) before editing them — always read first so you can make a precise targeted change. Also use for reading any text file on disk (logs, config files, scripts). Content is read as UTF-8. For large files, use the offset and length parameters to read in chunks; offsets are true character offsets, so multibyte UTF-8 content is chunked safely. Access is restricted to the directories configured via --file-root.")
		  
		  Parameters.Add(New MCPKit.ToolParameter("path", MCPKit.ToolParameterTypes.String_, _
		  "Absolute path to the file to read (e.g. /Users/you/GitHub/MyApp/src/Tools/MyTool.xojo_code). Must be inside an allowed file root.", _
		  False, "", True))
		  
		  Parameters.Add(New MCPKit.ToolParameter("offset", MCPKit.ToolParameterTypes.Integer_, _
		  "Character offset to start reading from. Default is 0 (start of file). Use with length for chunked reading of large files.", _
		  True, 0, False))
		  
		  Parameters.Add(New MCPKit.ToolParameter("length", MCPKit.ToolParameterTypes.Integer_, _
		  "Maximum number of characters to read. Default is 0, which means read the entire file. Use with offset for chunked reading.", _
		  True, 0, False))
		  
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Run(args() As MCPKit.ToolArgument) As MCPKit.ToolResult
		  Var path As String
		  Var offset As Int64 = 0
		  Var length As Int64 = 0
		  
		  // Parse arguments
		  For Each arg As MCPKit.ToolArgument In args
		    
		    Select Case arg.Name.Lowercase
		      
		    Case "path"
		      path = arg.Value.StringValue.Trim
		      
		    Case "offset"
		      offset = arg.Value.IntegerValue
		      
		    Case "length"
		      length = arg.Value.IntegerValue
		      
		    End Select
		    
		  Next
		  
		  // Validate
		  If path.IsEmpty Then
		    Return MCPKit.ToolResult.Failure("The path parameter is required.")
		  End If
		  
		  If offset < 0 Then
		    Return MCPKit.ToolResult.Failure("Offset cannot be negative.")
		  End If
		  
		  If length < 0 Then
		    Return MCPKit.ToolResult.Failure("Length cannot be negative.")
		  End If
		  
		  Var reason As String
		  Var allowed As Boolean = FileGuard.Validate(path, reason)
		  If Not allowed Then
		    Return MCPKit.ToolResult.Failure(reason)
		  End If
		  
		  Var f As New FolderItem(path, FolderItem.PathModes.Native)
		  
		  If f Is Nil Then
		    Return MCPKit.ToolResult.Failure("Invalid path: " + path)
		  End If
		  
		  If Not f.Exists Then
		    Return MCPKit.ToolResult.Failure("File not found: " + path)
		  End If
		  
		  If f.IsFolder Then
		    Return MCPKit.ToolResult.Failure("Path is a folder, not a file.")
		  End If
		  
		  Try
		    
		    // Read the whole file, then slice by CHARACTERS after decoding as
		    // UTF-8. Slicing decoded text (rather than raw bytes) means offset
		    // and length can never split a multibyte UTF-8 sequence.
		    Var bs As BinaryStream = BinaryStream.Open(f)
		    Var fileSize As Int64 = bs.Length
		    Var content As String = bs.Read(fileSize)
		    bs.Close
		    
		    content = content.DefineEncoding(Encodings.UTF8)
		    Var totalChars As Int64 = content.Length
		    
		    // Past end of content
		    If offset >= totalChars And totalChars > 0 Then
		      Return MCPKit.ToolResult.Success("")
		    End If
		    
		    Var slice As String
		    If length > 0 Then
		      slice = content.Middle(offset, length)
		    ElseIf offset > 0 Then
		      slice = content.Middle(offset)
		    Else
		      slice = content
		    End If
		    
		    // Build summary header — placed before content so it is never
		    // accidentally included if the caller writes content back to disk.
		    Var summary As String = "// read_file: " + f.Name + " (total " + totalChars.ToString + " characters"
		    If offset > 0 Or length > 0 Then
		      Var sliceChars As Int64 = slice.Length
		      Var lastChar As Int64 = offset + sliceChars - 1
		      summary = summary + ", returning characters " + offset.ToString + "-" + lastChar.ToString
		    End If
		    summary = summary + ")"
		    
		    Return MCPKit.ToolResult.Success(summary + EndOfLine + slice)
		    
		  Catch e As IOException
		    Return MCPKit.ToolResult.Failure("Read failed: " + e.Message)
		    
		  Catch e As RuntimeException
		    Return MCPKit.ToolResult.Failure("Read failed: " + e.Message)
		    
		  End Try
		  
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
