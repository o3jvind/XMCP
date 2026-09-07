#tag Class
Protected Class Docset
	#tag Method, Flags = &h0
		Sub Constructor(bundlePath As FolderItem)
		  // Lazy DB attach, same pattern as SemanticSearch.EnsureDatabase: a
		  // docset bundle whose dsidx is briefly unreadable at startup should
		  // not crash the server — it's simply unavailable until re-probed.
		  mBundlePath = bundlePath
		  mName = bundlePath.Name
		  If mName.Right(7) = ".docset" Then mName = mName.Left(mName.Length - 7)

		  mDocumentsPath = bundlePath.Child("Contents").Child("Resources").Child("Documents")
		  mHasDatabase = False
		  mTarixExtractAttempted = False
		  Call EnsureDatabase
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function EnsureDatabase() As Boolean
		  If mHasDatabase Then Return True

		  Var dsidx As FolderItem = mBundlePath.Child("Contents").Child("Resources").Child("docSet.dsidx")
		  If dsidx = Nil Or Not dsidx.Exists Then Return False

		  mDB = New SQLiteDatabase
		  mDB.DatabaseFile = dsidx
		  Try
		    mDB.Connect
		  Catch e As DatabaseException
		    mDB = Nil
		    Return False
		  End Try

		  mHasDatabase = True
		  Return True
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function EnsureDocuments() As Boolean
		  // Most docsets ship Contents/Resources/Documents/ directly. Some
		  // (e.g. Dash's disk-space-saving distributions) instead ship the
		  // same tree packed into Contents/Resources/tarix.tgz, with no
		  // Documents/ folder on disk at all. For those, extract the archive
		  // once into a per-docset cache under Application Support and read
		  // from there afterward — Xojo's FolderItem.Unzip only understands
		  // the ZIP format, not tar+gzip, so this shells out to the system
		  // `tar` binary (same approach as GetSystemLog's `log show` call).
		  If mDocumentsPath <> Nil And mDocumentsPath.Exists Then Return True
		  If mTarixExtractAttempted Then Return mDocumentsPath <> Nil And mDocumentsPath.Exists

		  mTarixExtractAttempted = True

		  Var tarixFile As FolderItem = mBundlePath.Child("Contents").Child("Resources").Child("tarix.tgz")
		  If tarixFile = Nil Or Not tarixFile.Exists Then Return False

		  // FolderItem.Child returns Nil if any path component up to the
		  // immediate parent doesn't exist yet on disk — it does not create
		  // intermediate folders the way the FolderItem constructor does for
		  // a path string. So each level below ApplicationData must be
		  // resolved and created (if missing) before descending further.
		  Var destFolder As FolderItem = EnsureCacheFolder(mName)
		  If destFolder = Nil Then Return False

		  Const kTarTimeoutMS = 120000 // large docsets can be 50+ MB compressed

		  Var sh As New Shell
		  sh.TimeOut = kTarTimeoutMS
		  sh.Execute("/usr/bin/tar -xzf " + EscapeShellArg(tarixFile.NativePath) + " -C " + EscapeShellArg(destFolder.NativePath))

		  If sh.ExitCode <> 0 Then Return False

		  // The archive contains the whole bundle (e.g. "AppleScript.docset/
		  // Contents/Resources/Documents/..."), not just the Documents subtree,
		  // so locate Documents/ wherever it landed inside the extracted tree.
		  Var extractedDocuments As FolderItem = FindDocumentsFolder(destFolder)
		  If extractedDocuments = Nil Then Return False

		  mDocumentsPath = extractedDocuments
		  Return True
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function EnsureCacheFolder(docsetName As String) As FolderItem
		  // Builds ~/Library/Application Support/dk.o3jvind.xmcp/docset-cache/<docsetName>/
		  // one level at a time, since FolderItem.Child returns Nil the moment
		  // any intermediate component is missing on disk.
		  Var appSupport As FolderItem = SpecialFolder.ApplicationData
		  If appSupport = Nil Or Not appSupport.Exists Then Return Nil

		  Var current As FolderItem = appSupport
		  For Each segment As String In Array("dk.o3jvind.xmcp", "docset-cache", docsetName)
		    Var next_ As FolderItem = current.Child(segment)
		    If next_ = Nil Then Return Nil

		    If Not next_.Exists Then
		      Try
		        next_.CreateFolder
		      Catch e As IOException
		        Return Nil
		      End Try
		    End If

		    current = next_
		  Next segment

		  Return current
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function EntryCount() As Integer
		  If Not EnsureDatabase Then Return 0

		  Try
		    Var rs As RowSet = mDB.SelectSQL("SELECT COUNT(*) AS n FROM searchIndex")
		    If rs = Nil Or Not rs.AfterLastRow = False Then Return 0
		    Return rs.Column("n").IntegerValue
		  Catch e As DatabaseException
		    Return 0
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function GetEntry(entryName As String) As String
		  // Returns "" if the entry, its HTML file, or the DB itself is
		  // unavailable — callers surface a ToolResult.Failure in that case.
		  If Not EnsureDatabase Then Return ""
		  If Not EnsureDocuments Then Return ""

		  Var path As String
		  Try
		    Var rs As RowSet = mDB.SelectSQL("SELECT path FROM searchIndex WHERE name = ?1 LIMIT 1", entryName)
		    If rs = Nil Or rs.AfterLastRow Then Return ""
		    path = rs.Column("path").StringValue
		  Catch e As DatabaseException
		    Return ""
		  End Try

		  If path = "" Then Return ""

		  // path may carry a trailing #anchor fragment — only the file part
		  // identifies what to read from Documents/; the anchor names a
		  // location within that file, which plain-text output can't scroll
		  // to, so it's dropped after locating the file.
		  Var relativeFile As String = path
		  Var hashPos As Integer = path.IndexOf("#")
		  If hashPos >= 0 Then relativeFile = path.Left(hashPos)

		  Var htmlFile As FolderItem = ResolveDocumentPath(relativeFile)
		  If htmlFile = Nil Or Not htmlFile.Exists Then Return ""

		  Try
		    Var tis As TextInputStream = TextInputStream.Open(htmlFile)
		    tis.Encoding = Encodings.UTF8
		    Var html As String = tis.ReadAll
		    tis.Close
		    Return StripHTML(html)
		  Catch e As IOException
		    Return ""
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function HasDatabase() As Boolean
		  Return EnsureDatabase
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function EscapeShellArg(value As String) As String
		  // Wrap in single quotes for /bin/sh, escaping any embedded single
		  // quote as '\'' (close quote, escaped quote, reopen quote).
		  Return "'" + value.ReplaceAll("'", "'\''") + "'"
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function FindDocumentsFolder(root As FolderItem) As FolderItem
		  // Breadth-limited search for a folder literally named "Documents"
		  // inside the extracted archive tree — its depth varies by docset
		  // (e.g. "<Name>.docset/Contents/Resources/Documents").
		  If root = Nil Or Not root.Exists Then Return Nil

		  For i As Integer = 0 To root.Count - 1
		    Var item As FolderItem = root.ChildAt(i)
		    If item = Nil Or Not item.IsFolder Then Continue

		    If item.Name = "Documents" Then Return item

		    Var found As FolderItem = FindDocumentsFolder(item)
		    If found <> Nil Then Return found
		  Next i

		  Return Nil
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ResolveDocumentPath(relativeFile As String) As FolderItem
		  // relativeFile uses "/" separators per the docset spec regardless of
		  // platform; walk it manually rather than relying on FolderItem's
		  // native-path parsing of a string containing "/".
		  Var result As FolderItem = mDocumentsPath
		  Var parts() As String = relativeFile.Split("/")
		  For Each part As String In parts
		    If part = "" Then Continue
		    If result = Nil Then Return Nil
		    result = result.Child(part)
		  Next part
		  Return result
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Search(query As String, maxResults As Integer) As String
		  If Not EnsureDatabase Then Return ""
		  If query = "" Then Return ""

		  Try
		    Var rs As RowSet = mDB.SelectSQL("SELECT name, type, path FROM searchIndex WHERE name LIKE ?1 ORDER BY name LIMIT ?2", "%" + query + "%", maxResults)
		    If rs = Nil Then Return ""

		    Var lines() As String
		    While Not rs.AfterLastRow
		      lines.Add(rs.Column("name").StringValue + " (" + rs.Column("type").StringValue + ") — " + rs.Column("path").StringValue)
		      rs.MoveToNextRow
		    Wend

		    If lines.Count = 0 Then Return ""
		    Return String.FromArray(lines, EndOfLine)
		  Catch e As DatabaseException
		    Return ""
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function StripHTML(html As String) As String
		  Var re As New RegEx
		  re.SearchPattern = "<[^<>]+>"
		  re.ReplacementPattern = ""
		  re.Options.ReplaceAllMatches = True
		  Var text As String = re.Replace(html)

		  text = text.ReplaceAll("&nbsp;", " ")
		  text = text.ReplaceAll("&amp;", "&")
		  text = text.ReplaceAll("&lt;", "<")
		  text = text.ReplaceAll("&gt;", ">")
		  text = text.ReplaceAll("&quot;", """")
		  text = text.ReplaceAll("&#39;", "'")

		  Return text
		End Function
	#tag EndMethod


	#tag Property, Flags = &h21
		Private mBundlePath As FolderItem
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mDB As SQLiteDatabase
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mDocumentsPath As FolderItem
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mHasDatabase As Boolean
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mName As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mTarixExtractAttempted As Boolean
	#tag EndProperty

	#tag ComputedProperty, Flags = &h0
		#tag Getter
			Get
			  Return mName
			End Get
		#tag EndGetter
		DocsetName As String
	#tag EndComputedProperty


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
End Class
#tag EndClass
