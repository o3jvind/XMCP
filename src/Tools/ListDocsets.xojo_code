#tag Class
Protected Class ListDocsets
Inherits MCPKit.Tool
	#tag Method, Flags = &h0
		Sub Constructor()
		  Super.Constructor("list_docsets", "Lists the Dash/Zeal .docset bundles registered via --docset-path, with their entry counts. Use this first to discover available docset names before calling search_docset or get_docset_entry.")

		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Run(args() As MCPKit.ToolArgument) As MCPKit.ToolResult
		  If App.Docsets = Nil Or App.Docsets.Count = 0 Then
		    Return MCPKit.ToolResult.Failure("No docsets configured. Use --docset-path to register one or more Dash/Zeal .docset bundles.")
		  End If

		  Var lines() As String
		  For Each ds As Docset In App.Docsets
		    If ds.HasDatabase Then
		      lines.Add(ds.DocsetName + " — " + ds.EntryCount.ToString + " entries")
		    Else
		      lines.Add(ds.DocsetName + " — unavailable (could not open docSet.dsidx)")
		    End If
		  Next ds

		  Return MCPKit.ToolResult.Success(String.FromArray(lines, EndOfLine))

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
