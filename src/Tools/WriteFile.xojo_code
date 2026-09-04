#tag Class
Protected Class WriteFile
Inherits MCPKit.Tool
	#tag Method, Flags = &h0
		Sub Constructor()
		  Super.Constructor("write_file", "Writes text content to a file on disk. Creates the file if it does not exist; overwrites it if it does. Use this to edit Xojo source files (.xojo_code, .xojo_window, .xojo_project) directly on disk — the primary workflow for all code changes. After writing, call revert_project to reload the project in the IDE. Content is written as UTF-8. Parent directories must already exist. Pass expected_hash to refuse the write if the file changed since you last read it. Access is restricted to the directories configured via --file-root.")
		  
		  Parameters.Add(New MCPKit.ToolParameter("path", MCPKit.ToolParameterTypes.String_, _
		  "Absolute path to the file to write (e.g. /Users/you/GitHub/MyApp/src/Tools/MyTool.xojo_code). Must be inside an allowed file root.", _
		  False, "", True))
		  
		  Parameters.Add(New MCPKit.ToolParameter("content", MCPKit.ToolParameterTypes.String_, _
		  "The full text content to write to the file. Existing content is replaced entirely.", _
		  False, "", True))

		  Parameters.Add(New MCPKit.ToolParameter("expected_hash", MCPKit.ToolParameterTypes.String_, _
		  "Optional MD5 or SHA-256 hex digest that the file is expected to have right now, as returned by hash_file. When supplied, the write is refused if the file has changed since then, so an edit made meanwhile by the user or another agent is never silently overwritten. The algorithm is inferred from the digest length.", _
		  True, "", False))
		  
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Run(args() As MCPKit.ToolArgument) As MCPKit.ToolResult
		  Var path As String
		  Var content As String
		  Var expectedHash As String
		  
		  For Each arg As MCPKit.ToolArgument In args
		    Select Case arg.Name.Lowercase
		    Case "path"
		      path = arg.Value.StringValue.Trim
		    Case "content"
		      content = arg.Value.StringValue
		    Case "expected_hash"
		      expectedHash = arg.Value.StringValue.Trim.Lowercase
		    End Select
		  Next arg
		  
		  If path.IsEmpty Then
		    Return MCPKit.ToolResult.Failure("The path parameter is required and cannot be empty.")
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
		  
		  If Not f.Parent.Exists Then
		    Return MCPKit.ToolResult.Failure("Parent directory does not exist: " + f.Parent.NativePath)
		  End If

		  // Optimistic concurrency: the caller states the digest it last saw, and the
		  // write is refused if the file has moved on. Opt-in, so existing callers
		  // are unaffected -- but without it nothing stops this tool from discarding
		  // an edit made between the caller's read and its write.
		  If expectedHash <> "" Then
		    Var algo As String = FileDigest.AlgorithmForDigest(expectedHash)
		    If algo = "" Then
		      Return MCPKit.ToolResult.Failure("expected_hash must be a 32-character MD5 or 64-character SHA-256 hex digest; got " + expectedHash.Length.ToString + " characters.")
		    End If

		    If Not f.Exists Then
		      Return MCPKit.ToolResult.Failure("expected_hash was supplied but no file exists at " + path + ". Omit expected_hash to create it.")
		    End If

		    Var digestError As String
		    Var actual As String = FileDigest.OfFile(f, algo, digestError)
		    If actual = "" Then
		      Return MCPKit.ToolResult.Failure(digestError)
		    End If

		    If actual <> expectedHash Then
		      Return MCPKit.ToolResult.Failure("Refusing to write: " + path + " has changed since it was hashed. Expected " + algo + " " + expectedHash + ", found " + actual + ". Re-read the file, reapply the change, then write again.")
		    End If
		  End If
		  
		  Try
		    Var stream As TextOutputStream = TextOutputStream.Create(f)
		    If stream Is Nil Then
		      Return MCPKit.ToolResult.Failure("Could not create file at: " + path)
		    End If
		    stream.Encoding = Encodings.UTF8
		    stream.Write(content)
		    stream.Close
		  Catch e As IOException
		    Return MCPKit.ToolResult.Failure("Write failed: " + e.Message + " (path: " + path + ")")
		  End Try
		  
		  Return MCPKit.ToolResult.Success("Written " + content.Length.ToString + " characters to " + path)
		  
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
