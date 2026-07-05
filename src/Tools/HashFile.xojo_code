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
		  
		  Try
		    
		    Var bs As BinaryStream = BinaryStream.Open(f)
		    Var hash As String
		    
		    Select Case algorithm
		    Case "md5"
		      hash = StreamMD5(bs)
		    Case "sha256"
		      hash = StreamSHA256(bs)
		    Else
		      bs.Close
		      Return MCPKit.ToolResult.Failure("Unknown algorithm '" + algorithm + "'. Use 'md5' or 'sha256'.")
		    End Select
		    
		    bs.Close
		    
		    Return MCPKit.ToolResult.Success(algorithm + ": " + hash + "  " + f.Name)
		    
		  Catch e As IOException
		    Return MCPKit.ToolResult.Failure("Unable to read file: " + e.Message)
		    
		  Catch e As RuntimeException
		    Return MCPKit.ToolResult.Failure("Hashing failed: " + e.Message)
		    
		  End Try
		  
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function StreamMD5(bs As BinaryStream) As String
		  // Incrementally hash the stream in 1 MB chunks so files of arbitrary
		  // size never require a whole-file MemoryBlock.
		  
		  Var chunkSize As Integer = 1048576
		  Var digest As New MD5Digest
		  
		  While Not bs.EndOfFile
		    Var chunk As String = bs.Read(chunkSize)
		    digest.Process(chunk)
		  Wend
		  
		  Var raw As String = digest.Value
		  Var hexed As String = EncodeHex(raw)
		  Return hexed.Lowercase
		  
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function StreamSHA256(bs As BinaryStream) As String
		  // Xojo has no incremental SHA-256 class (only the one-shot
		  // Crypto.SHA2_256), so on macOS we stream through CommonCrypto.
		  // On other platforms we fall back to a whole-file read — a known
		  // limitation until Xojo gains an incremental SHA-2 API.
		  
		  #If TargetMacOS Then
		    Declare Function CC_SHA256_Init Lib "/usr/lib/libSystem.dylib" (ctx As Ptr) As Integer
		    Declare Function CC_SHA256_Update Lib "/usr/lib/libSystem.dylib" (ctx As Ptr, data As Ptr, length As UInt32) As Integer
		    Declare Function CC_SHA256_Final Lib "/usr/lib/libSystem.dylib" (md As Ptr, ctx As Ptr) As Integer
		    
		    // CC_SHA256_CTX is 104 bytes; allocate a little extra for safety.
		    Var chunkSize As Integer = 1048576
		    Var ctx As New MemoryBlock(112)
		    Call CC_SHA256_Init(ctx)
		    
		    While Not bs.EndOfFile
		      Var chunk As String = bs.Read(chunkSize)
		      Var mb As MemoryBlock = chunk
		      Call CC_SHA256_Update(ctx, mb, mb.Size)
		    Wend
		    
		    Var out As New MemoryBlock(32)
		    Call CC_SHA256_Final(out, ctx)
		    
		    Var raw As String = out.StringValue(0, 32)
		    Var hexed As String = EncodeHex(raw)
		    Return hexed.Lowercase
		  #Else
		    Var data As MemoryBlock = bs.Read(bs.Length)
		    Var raw As String = Crypto.SHA2_256(data)
		    Var hexed As String = EncodeHex(raw)
		    Return hexed.Lowercase
		  #EndIf
		  
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
