#tag Class
Protected Class HashFile
Inherits MCPKit.Tool
	#tag Method, Flags = &h0
		Sub Constructor()
		  Super.Constructor("hash_file", "Returns the MD5 or SHA-256 hex digest of a file on disk. Use this to verify that a write_file operation landed correctly — call hash_file before and after writing to confirm the content changed as expected, or call it after writing and compare against a known-good hash. Also useful to detect whether a file has changed between sessions. Files are hashed in 1 MB chunks, so arbitrarily large files are supported. Access is restricted to the directories configured via --file-root.")
		  
		  Parameters.Add(New MCPKit.ToolParameter("path", MCPKit.ToolParameterTypes.String_, _
		  "Absolute path to the file to hash (e.g. /Users/you/GitHub/MyApp/src/Tools/MyTool.xojo_code). Must be inside an allowed file root.", _
		  False, "", True))
		  
		  Parameters.Add(New MCPKit.ToolParameter("algorithm", MCPKit.ToolParameterTypes.String_, _
		  "Hash algorithm to use: ""md5"" (default) or ""sha256"".", _
		  True, "md5", False))
		  
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Run(args() As MCPKit.ToolArgument) As MCPKit.ToolResult
		  Var path As String
		  Var algorithm As String = "md5"
		  
		  // Parse arguments
		  For Each arg As MCPKit.ToolArgument In args
		    Select Case arg.Name.Lowercase
		    Case "path"
		      path = arg.Value.StringValue.Trim
		    Case "algorithm"
		      algorithm = arg.Value.StringValue.Trim.Lowercase
		    End Select
		  Next
		  
		  // Validate
		  If path.IsEmpty Then
		    Return MCPKit.ToolResult.Failure("The path parameter is required.")
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
		    Return MCPKit.ToolResult.Failure("Path is a folder, not a file: " + path)
		  End If
		  
		  Var digestError As String
		  Var hash As String = FileDigest.OfFile(f, algorithm, digestError)

		  If hash = "" Then
		    Return MCPKit.ToolResult.Failure(digestError)
		  End If

		  Return MCPKit.ToolResult.Success(algorithm + ": " + hash + "  " + f.Name)
		  
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
