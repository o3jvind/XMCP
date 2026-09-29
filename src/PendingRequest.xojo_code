#tag Class
Protected Class PendingRequest
	#tag Method, Flags = &h0
		Sub Constructor(replySocket As IPCSocket, requestTag As String, requestScript As String, endMarkerExpected As Boolean, unframed As String)
		  Sock = replySocket
		  Tag = requestTag
		  Script = requestScript
		  MarkerExpected = endMarkerExpected
		  // The start of a part the live reader had read when the request parked, if any: the rest
		  // arrives here, and the part can only be read whole.
		  Buffer = unframed
		  SinceUS = System.Microseconds
		  LastDataUS = System.Microseconds
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function ReplyComplete(owner As IDECommunicator) As Boolean
		  /// Takes whatever the IDE has written so far and reports whether this request's answer
		  /// is complete, so its socket can be closed. The caller polls the socket first.
		  ///
		  /// Decided by the same rule as the live reader in IDECommunicator, with the same
		  /// tests (owner.IsEndMarker, owner.StopsScript): the answer is complete when its end
		  /// marker has arrived, or a compile or runtime error that stopped the script. A part
		  /// followed by a quiet spell is not enough. The IDE sends each Print the moment it runs,
		  /// so a script that prints, then waits on a build or a dialog, then prints again goes
		  /// quiet in between - and closing then is the SIGPIPE parking exists to prevent: the
		  /// IDE writes the rest into a closed peer. Parts for another tag say nothing about this
		  /// request and are ignored.
		  ///
		  /// A script that ends in a line continuation has no marker appended, so for it any part of
		  /// its own that is not warnings alone ends the answer - the live reader's rule for it. On top of either, the connection must have
		  /// been quiet for kQuietAfterFrameMS, so that a trailing warning is in before the close.
		  ///
		  /// Parts are NUL-terminated JSON; on Windows the transport is TCP, which splits a large
		  /// part across reads, so only whole parts are looked at and a partial one stays in the
		  /// buffer. What the parts say is discarded: the caller gave up on this request long ago.
		  
		  Var chunk As String = Sock.ReadAll
		  If chunk <> "" Then
		    Buffer = Buffer + chunk
		    LastDataUS = System.Microseconds
		  End If
		  
		  Var nulPos As Integer = Buffer.IndexOf(Chr(0))
		  While nulPos >= 0
		    Var frame As String = Buffer.Left(nulPos).Trim
		    Buffer = Buffer.Middle(nulPos + 1)
		    nulPos = Buffer.IndexOf(Chr(0))
		    If frame = "" Then Continue
		    
		    Try
		      Var response As New JSONItem(frame)
		      If response.HasKey("tag") And response.Value("tag").StringValue = Tag Then
		        If MarkerExpected Then
		          If owner.IsEndMarker(response, Tag) Or owner.StopsScript(response) Then AnswerEnded = True
		        ElseIf owner.ReplyKind(response) <> "warning" Then
		          // No marker is coming. As in the live reader, a part of warnings alone does not end
		          // the answer - the output it is about is still to come - and any other part does.
		          AnswerEnded = True
		        End If
		      End If
		    Catch e As RuntimeException
		      // A part that cannot be read is skipped, as in the live reader.
		    End Try
		  Wend
		  
		  If Not AnswerEnded Then Return False
		  Return System.Microseconds - LastDataUS >= kQuietAfterFrameMS * 1000.0
		End Function
	#tag EndMethod


	#tag Note, Name = Why a parked socket is held open
		One request the IDE accepted but has not answered yet, and the socket it arrived on.
		
		The socket is held open rather than closed: the IDE runs scripts one at a time on its
		main thread, so a build or a modal dialog can leave a request unanswered for minutes,
		and a write into a closed peer raises SIGPIPE, which the Xojo IDE does not ignore.
		IDECommunicator.DrainPending polls these and releases the ones the IDE has finished
		with.
		
		This replaces four parallel arrays. The buffer is why: a reply is whole only once its
		NUL terminator arrives, and tracking a fifth array alongside the other four to know
		that would be worse than carrying the state together.
	#tag EndNote


	#tag Property, Flags = &h0
		AnswerEnded As Boolean
	#tag EndProperty

	#tag Property, Flags = &h0
		Buffer As String
	#tag EndProperty

	#tag Property, Flags = &h0
		LastDataUS As Double
	#tag EndProperty

	#tag Property, Flags = &h0
		MarkerExpected As Boolean
	#tag EndProperty

	#tag Property, Flags = &h0
		Script As String
	#tag EndProperty

	#tag Property, Flags = &h0
		SinceUS As Double
	#tag EndProperty

	#tag Property, Flags = &h0
		Sock As IPCSocket
	#tag EndProperty

	#tag Property, Flags = &h0
		Tag As String
	#tag EndProperty

	#tag Constant, Name = kQuietAfterFrameMS, Type = Double, Dynamic = False, Default = \"250", Scope = Private
	#tag EndConstant


End Class
#tag EndClass
