#tag Module
Protected Module FileDigest
	#tag Method, Flags = &h0
		Function OfFile(f As FolderItem, algorithm As String, ByRef errorMessage As String) As String
		  /// Lowercase hex digest of a file, or "" with errorMessage set.
		  /// Shared by hash_file and by write_file's staleness check so the two can
		  /// never disagree about what the digest of a given file is.

		  errorMessage = ""

		  If f Is Nil Then
		    errorMessage = "Invalid file."
		    Return ""
		  End If

		  If Not f.Exists Then
		    errorMessage = "File not found: " + f.NativePath
		    Return ""
		  End If

		  If f.IsFolder Then
		    errorMessage = "Path is a folder, not a file: " + f.NativePath
		    Return ""
		  End If

		  Var algo As String = algorithm.Trim.Lowercase
		  If algo = "" Then
		    algo = "md5"
		  End If

		  If algo <> "md5" And algo <> "sha256" Then
		    errorMessage = "Unknown algorithm '" + algorithm + "'. Use 'md5' or 'sha256'."
		    Return ""
		  End If

		  Try
		    Var bs As BinaryStream = BinaryStream.Open(f)
		    Var hash As String

		    If algo = "md5" Then
		      hash = StreamMD5(bs)
		    Else
		      hash = StreamSHA256(bs)
		    End If

		    bs.Close
		    Return hash

		  Catch e As IOException
		    errorMessage = "Unable to read file: " + e.Message
		    Return ""

		  Catch e As RuntimeException
		    errorMessage = "Hashing failed: " + e.Message
		    Return ""
		  End Try

		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function AlgorithmForDigest(digest As String) As String
		  /// Infers the algorithm from a hex digest's length so a caller can supply
		  /// an expected hash without also naming the algorithm that produced it.
		  /// Returns "" when the length matches neither.

		  Var n As Integer = digest.Trim.Length

		  If n = 32 Then
		    Return "md5"
		  ElseIf n = 64 Then
		    Return "sha256"
		  End If

		  Return ""

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

	#tag Note, Name = DesignNotes
		FileDigest exists so that write_file's staleness guard and hash_file compute
		digests through exactly the same code. If the two ever diverged, a guard that
		silently disagreed with the tool used to obtain the expected hash would be
		worse than no guard at all.
	#tag EndNote

	#tag ViewBehavior
		#tag ViewProperty
			Name="Name"
			Visible=true
			Group="ID"
			InitialValue=""
			Type="String"
			EditorType=""
		#tag EndViewProperty
	#tag EndViewBehavior
End Module
#tag EndModule
