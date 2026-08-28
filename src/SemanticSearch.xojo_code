#tag Class
Protected Class SemanticSearch
	#tag Method, Flags = &h0
		Sub Constructor(embeddingUrl As String, rerankUrl As String, dbPath As String)
		  // Task 13: the DB connection and the embedding server are independent
		  // tiers. A reachable DB alone enables keyword (BM25) search; the
		  // embedding server upgrades it to hybrid semantic search. Both are
		  // (re-)checked lazily at search time — XMCP typically starts with the
		  // editor, i.e. BEFORE XDOX, so neither may exist yet at this point.
		  //
		  // The reranker is a THIRD, independently-degradable tier layered on top
		  // of hybrid search — XDOX owns its lifecycle (model download, the
		  // llama-server process); XMCP only ever probes it. A reranker that's
		  // down or was never installed must not disable base hybrid search, so
		  // its availability is tracked separately from mAvailable and probed
		  // with its own cooldown.
		  mEmbeddingUrl = embeddingUrl
		  mRerankUrl = rerankUrl
		  mDbPath = dbPath
		  mAvailable = False
		  mRerankAvailable = False
		  mHasDatabase = False

		  Call EnsureDatabase
		  EnsureAvailable
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function EnsureDatabase() As Boolean
		  // Lazy DB attach: cheap flag check once connected; a missing file is
		  // re-stat'ed on every call so a DB created after startup (first XDOX
		  // launch, reindex after schema bump) is picked up automatically.
		  If mHasDatabase Then Return True

		  Var dbFile As New FolderItem(mDbPath, FolderItem.PathModes.Native)
		  If dbFile = Nil Or Not dbFile.Exists Then Return False

		  mDB = New SQLiteDatabase
		  mDB.DatabaseFile = dbFile
		  Try
		    mDB.Connect
		  Catch e As DatabaseException
		    mDB = Nil
		    Return False
		  End Try

		  // Performance pragmas: WAL mode for non-blocking reads, memory-mapped I/O,
		  // and a 64 MB page cache so the embedding BLOBs stay warm between searches.
		  // XDOX (the writer) may be indexing concurrently; WAL makes reads safe.
		  Try
		    mDB.ExecuteSQL("PRAGMA journal_mode=WAL")
		    mDB.ExecuteSQL("PRAGMA mmap_size=268435456")
		    mDB.ExecuteSQL("PRAGMA cache_size=-65536")
		  Catch
		    // Non-fatal; continue with defaults.
		  End Try

		  mHasDatabase = True
		  ReadMetadata
		  Return True
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub EnsureAvailable()
		  // Lazy server probe with a cooldown: a down embedding server costs one
		  // 2 s probe per kProbeCooldownMicros window, not one per search.
		  If mAvailable Then Return
		  If Not EnsureDatabase Then Return

		  // Validate embedding compatibility: the cosine path assumes 768-dim
		  // nomic float32 BLOBs. A DB built with another model must not be
		  // scored semantically — keyword search still works.
		  If mEmbeddingDim > 0 And mEmbeddingDim <> 768 Then
		    If Not mDimWarned Then
		      mDimWarned = True
		      System.DebugLog("SemanticSearch: DB uses " + mEmbeddingDim.ToString + "-dim embeddings (expected 768) — semantic tier disabled.")
		    End If
		    Return
		  End If

		  If mLastProbeMicros > 0 And Microseconds - mLastProbeMicros < kProbeCooldownMicros Then Return
		  mLastProbeMicros = Microseconds

		  Var testEmb As MemoryBlock = FetchEmbedding("test", 2000)
		  If testEmb = Nil Then Return

		  mAvailable = True
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub EnsureRerankAvailable()
		  // Same lazy-probe-with-cooldown pattern as EnsureAvailable, but kept
		  // fully independent: a down/never-installed reranker degrades Search()
		  // back to cosine+BM25 ordering, it never disables hybrid search itself.
		  If mRerankAvailable Then Return

		  If mLastRerankProbeMicros > 0 And Microseconds - mLastRerankProbeMicros < kProbeCooldownMicros Then Return
		  mLastRerankProbeMicros = Microseconds

		  Var testScores() As Double = FetchRerankScores("test", Array("test document"), 2000)
		  If testScores.Count = 0 Then Return

		  mRerankAvailable = True
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function HasDatabase() As Boolean
		  Return EnsureDatabase
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function DocsVersion() As String
		  Return mDocsVersion
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub ReadMetadata()
		  // The metadata table exists in XDOX DBs and indexer DBs >= 0.2.0;
		  // its absence just means "no validation possible".
		  Try
		    Var rs As RowSet = mDB.SelectSQL("SELECT key, value FROM metadata")
		    Do Until rs.AfterLastRow
		      Select Case rs.Column("key").StringValue
		      Case "embedding_dim"
		        mEmbeddingDim = rs.Column("value").StringValue.ToInteger
		      Case "docs_version"
		        mDocsVersion = rs.Column("value").StringValue
		      End Select
		      rs.MoveToNextRow
		    Loop
		    rs.Close
		  Catch e As DatabaseException
		    // No metadata table — legacy DB, carry on.
		  End Try

		  // Multi-version support (XDOX schema v3): chunks carry a docs_version and
		  // notes carry a scope. Older/legacy DBs (xojo_rag.db, schema < 3) lack
		  // these columns, so probe once and gate the version/scope filters on their
		  // presence — otherwise the added WHERE clauses would throw and silently
		  // return no results against an older database.
		  mHasChunkVersion = ColumnExists("chunks", "docs_version")
		  mHasNoteScope = ColumnExists("notes", "scope")
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ColumnExists(tableName As String, columnName As String) As Boolean
		  // PRAGMA table_info can't take a bound parameter for the table name in all
		  // SQLite builds, so the name is inlined. tableName is a compile-time
		  // constant here ("chunks"/"notes"), never user input — no injection risk.
		  If mDB = Nil Then Return False
		  Try
		    Var rs As RowSet = mDB.SelectSQL("PRAGMA table_info(" + tableName + ")")
		    Var found As Boolean = False
		    Do Until rs.AfterLastRow
		      If rs.Column("name").StringValue = columnName Then
		        found = True
		        Exit
		      End If
		      rs.MoveToNextRow
		    Loop
		    rs.Close
		    Return found
		  Catch e As DatabaseException
		    Return False
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ActiveDocsVersion() As String
		  // The Xojo version chat/retrieval currently filters on, read fresh on each
		  // search so XMCP tracks XDOX's live version switch (XDOX may change it
		  // while we hold this connection). Falls back to the last-indexed
		  // docs_version, then "" — an empty value means "no filter" (match all).
		  If mDB = Nil Then Return mDocsVersion
		  Try
		    Var rs As RowSet = mDB.SelectSQL("SELECT value FROM metadata WHERE key = 'active_docs_version'")
		    Var v As String = ""
		    If Not rs.AfterLastRow Then v = rs.Column("value").StringValue
		    rs.Close
		    If v <> "" Then Return v
		  Catch e As DatabaseException
		    // No metadata table — fall through to the indexed version.
		  End Try
		  Return mDocsVersion
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function KeywordSearch(query As String, maxResults As Integer) As String
		  // BM25-only tier: works with just the DB file, no embedding server.
		  // Replaces the old llms-full.txt substring scan as the primary fallback.
		  If Not EnsureDatabase Then Return ""

		  Var safe As String = BuildMatchQuery(query)
		  If safe = "" Then Return ""

		  // Multi-version: restrict to the active version plus version-independent
		  // chunks (docs_version='') and MBS docset chunks (docs_version=kMBSDocsVersion,
		  // always included regardless of active Xojo version). Skipped on legacy
		  // DBs without the column. Keep this filter in sync with XDOX
		  // Retrieval.KeywordSearchChunks.
		  Var activeVersion As String = ActiveDocsVersion
		  Var versionClause As String = ""
		  If mHasChunkVersion Then versionClause = "AND (c.docs_version = ? OR c.docs_version = '' OR c.docs_version = ?) "

		  Var results() As String
		  Try
		    Var sql As String = "SELECT c.title, c.chunk_text, c.prev_id, c.next_id, bm25(chunks_fts) AS score " _
		      + "FROM chunks_fts JOIN chunks c ON c.id = chunks_fts.rowid " _
		      + "WHERE chunks_fts MATCH ? " + versionClause + "ORDER BY score LIMIT ?"
		    Var rs As RowSet
		    If mHasChunkVersion Then
		      rs = mDB.SelectSQL(sql, safe, activeVersion, kMBSDocsVersion, maxResults)
		    Else
		      rs = mDB.SelectSQL(sql, safe, maxResults)
		    End If
		    Do Until rs.AfterLastRow
		      results.Add("--- " + rs.Column("title").StringValue + " ---" + EndOfLine + rs.Column("chunk_text").StringValue)
		      rs.MoveToNextRow
		    Loop
		    rs.Close
		  Catch e As DatabaseException
		    Return ""
		  End Try

		  If results.Count = 0 Then Return ""

		  Var header As String = "Found " + results.Count.ToString + " result(s) for """ + query + """ (keyword"
		  Var headerVersion As String = If(activeVersion <> "", activeVersion, mDocsVersion)
		  If headerVersion <> "" Then header = header + ", " + headerVersion
		  header = header + "):"
		  Return header + EndOfLine + EndOfLine + String.FromArray(results, EndOfLine + EndOfLine)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function SearchNotes(query As String, maxResults As Integer) As String
		  // Tiered notes search: hybrid (cosine + BM25) when the embedding server
		  // answers, keyword-only otherwise. Mirrors XDOX's Retrieval.SearchNotes
		  // so natural-language queries find notes that share no keywords.
		  EnsureAvailable
		  If mAvailable Then
		    Var hybrid As String = SearchNotesHybrid(query, maxResults)
		    If hybrid <> "" Then Return hybrid
		  End If
		  Return SearchNotesKeyword(query, maxResults)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function SearchNotesHybrid(query As String, maxResults As Integer) As String
		  // Ported from XDOX Retrieval.HybridSearchNotes: 0.7·cosine + 0.3·BM25,
		  // relevance floor 0.45 so unrelated notes stay out of results.
		  If mDB = Nil Then Return ""

		  Var queryEmb As MemoryBlock = FetchEmbedding(query)
		  If queryEmb = Nil Then
		    mAvailable = False
		    mLastProbeMicros = Microseconds
		    Return ""
		  End If

		  Var rowids() As Integer
		  Var titles() As String
		  Var bodies() As String
		  Var tagsArr() As String
		  Var versions() As String
		  Var scopes() As String
		  Var warned() As Boolean
		  Var cosScores() As Double

		  // All notes stay searchable regardless of scope; the scope column only
		  // governs the outdated label (global notes never carry it). Selected
		  // conditionally so legacy DBs without the column still work.
		  Var scopeCol As String = If(mHasNoteScope, "n.scope", "'' AS scope")

		  Try
		    Var rs As RowSet = mDB.SelectSQL( _
		      "SELECT n.rowid AS rid, n.title, n.body, n.tags, n.docs_version, n.version_warned, " + scopeCol + ", e.embedding " _
		      + "FROM note_embeddings e JOIN notes n ON e.note_id = n.id")
		    Do Until rs.AfterLastRow
		      Var embBlob As MemoryBlock = rs.Column("embedding").BlobValue
		      If embBlob <> Nil And embBlob.Size > 0 Then
		        rowids.Add(rs.Column("rid").IntegerValue)
		        titles.Add(rs.Column("title").StringValue)
		        bodies.Add(rs.Column("body").StringValue)
		        tagsArr.Add(rs.Column("tags").StringValue)
		        versions.Add(rs.Column("docs_version").StringValue)
		        scopes.Add(rs.Column("scope").StringValue)
		        warned.Add(rs.Column("version_warned").IntegerValue = 1)
		        cosScores.Add(CosineSimilarity(queryEmb, embBlob))
		      End If
		      rs.MoveToNextRow
		    Loop
		    rs.Close
		  Catch e As DatabaseException
		    // note_embeddings absent (legacy DB) — keyword tier handles it.
		    Return ""
		  End Try
		  If rowids.Count = 0 Then Return ""

		  // BM25 leg over notes_fts (rowid-keyed), normalised like the docs path.
		  Var ftsScores() As Double
		  For i As Integer = 0 To rowids.LastIndex
		    ftsScores.Add(0.0)
		  Next i
		  Var safe As String = BuildMatchQuery(query)
		  If safe <> "" Then
		    Try
		      Var ftsMap As New Dictionary
		      // ORDER BY is load-bearing — see the chunks-leg fix below for why
		      // an unordered LIMIT on a broad OR-matched query silently drops
		      // the actually-relevant rows (confirmed live on the XDOX side).
		      Var ftsRS As RowSet = mDB.SelectSQL( _
		        "SELECT rowid, bm25(notes_fts) AS s FROM notes_fts WHERE notes_fts MATCH ? ORDER BY bm25(notes_fts) LIMIT 100", safe)
		      Do Until ftsRS.AfterLastRow
		        ftsMap.Value(ftsRS.Column("rowid").IntegerValue) = 1.0 / (1.0 + Exp(ftsRS.Column("s").DoubleValue * 0.5))
		        ftsRS.MoveToNextRow
		      Loop
		      ftsRS.Close
		      // NOT CDbl(Variant) — confirmed live on the XDOX side (same
		      // pattern, ported here) to mis-parse a Double-typed Dictionary
		      // Variant under a comma-decimal locale, inflating e.g. 0.097 to
		      // ~9.7e14. DoubleValue reads the Variant's binary double directly.
		      For i As Integer = 0 To rowids.LastIndex
		        If ftsMap.HasKey(rowids(i)) Then ftsScores(i) = ftsMap.Value(rowids(i)).DoubleValue
		      Next i
		    Catch e As DatabaseException
		      // FTS unavailable — cosine-only.
		    End Try
		  End If

		  Var combined() As Double
		  For i As Integer = 0 To cosScores.LastIndex
		    combined.Add(cosScores(i) * 0.7 + ftsScores(i) * 0.3)
		  Next i

		  Var used() As Boolean
		  For i As Integer = 0 To combined.LastIndex
		    used.Add(False)
		  Next i

		  Var results() As String
		  For r As Integer = 1 To maxResults
		    Var bestIdx As Integer = -1
		    Var bestScore As Double = kNoteRelevanceFloor
		    For i As Integer = 0 To combined.LastIndex
		      If Not used(i) And combined(i) > bestScore Then
		        bestScore = combined(i)
		        bestIdx = i
		      End If
		    Next i
		    If bestIdx < 0 Then Exit
		    used(bestIdx) = True

		    Var entry As String = "--- " + titles(bestIdx)
		    // Global notes (scope='all') are version-independent and never labelled;
		    // only version-scoped notes carry the outdated caveat. On legacy DBs
		    // without the scope column, keep the old warned-only behaviour.
		    Var scopedVersion As Boolean = If(mHasNoteScope, scopes(bestIdx) = "version", True)
		    If scopedVersion And warned(bestIdx) And versions(bestIdx) <> "" Then
		      entry = entry + " [possibly outdated — written for " + versions(bestIdx) + "]"
		    End If
		    entry = entry + " ---" + EndOfLine + bodies(bestIdx)
		    If tagsArr(bestIdx) <> "" Then entry = entry + EndOfLine + "(tags: " + tagsArr(bestIdx) + ")"
		    results.Add(entry)
		  Next r

		  If results.Count = 0 Then Return ""
		  Return "Found " + results.Count.ToString + " note(s) for """ + query + """ (semantic):" _
		    + EndOfLine + EndOfLine + String.FromArray(results, EndOfLine + EndOfLine)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function SearchNotesKeyword(query As String, maxResults As Integer) As String
		  // BM25 over the user's personal notes (XDOX DBs only — legacy
		  // xojo_rag.db has no notes tables; that case returns "" gracefully).
		  If Not EnsureDatabase Then Return ""

		  Var safe As String = BuildMatchQuery(query)
		  If safe = "" Then Return ""

		  // All notes searchable regardless of scope; scope only governs the
		  // outdated label. Column selected conditionally for legacy-DB safety.
		  Var scopeCol As String = If(mHasNoteScope, "n.scope", "'' AS scope")

		  Var results() As String
		  Try
		    Var rs As RowSet = mDB.SelectSQL( _
		      "SELECT n.title, n.body, n.tags, n.docs_version, n.version_warned, " + scopeCol + " " _
		      + "FROM notes_fts JOIN notes n ON n.rowid = notes_fts.rowid " _
		      + "WHERE notes_fts MATCH ? ORDER BY bm25(notes_fts) LIMIT ?", safe, maxResults)
		    Do Until rs.AfterLastRow
		      Var entry As String = "--- " + rs.Column("title").StringValue
		      Var noteVersion As String = rs.Column("docs_version").StringValue
		      // Global notes never carry the caveat; legacy DBs keep warned-only.
		      Var scopedVersion As Boolean = If(mHasNoteScope, rs.Column("scope").StringValue = "version", True)
		      If scopedVersion And rs.Column("version_warned").IntegerValue = 1 And noteVersion <> "" Then
		        entry = entry + " [possibly outdated — written for " + noteVersion + "]"
		      End If
		      entry = entry + " ---" + EndOfLine + rs.Column("body").StringValue
		      Var tags As String = rs.Column("tags").StringValue
		      If tags <> "" Then entry = entry + EndOfLine + "(tags: " + tags + ")"
		      results.Add(entry)
		      rs.MoveToNextRow
		    Loop
		    rs.Close
		  Catch e As DatabaseException
		    // notes tables absent (legacy DB) — not an error.
		    Return ""
		  End Try

		  If results.Count = 0 Then Return ""
		  Return "Found " + results.Count.ToString + " note(s) for """ + query + """:" _
		    + EndOfLine + EndOfLine + String.FromArray(results, EndOfLine + EndOfLine)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function SanitizeFTSQuery(query As String) As String
		  // FTS5 MATCH chokes on raw quotes/operators — strip them (same rules
		  // as XDOX's Retrieval.SanitizeQuery).
		  Var s As String = query
		  Var specials() As String = Array("""", "'", "*", "^", "(", ")", "[", "]", "{", "}", "~", ":", "\", "/", "-", "?", "!", ".", ",", ";")
		  For Each ch As String In specials
		    s = s.ReplaceAll(ch, " ")
		  Next
		  While s.IndexOf("  ") >= 0
		    s = s.ReplaceAll("  ", " ")
		  Wend
		  Return s.Trim
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function BuildMatchQuery(query As String) As String
		  // FTS5's default MATCH is an implicit AND across all tokens, so a
		  // conversational query almost never matches terse reference text and
		  // returns zero rows. OR-joining lets any token match. Keep in sync
		  // with XDOX Retrieval.BuildMatchQuery.
		  Var safe As String = SanitizeFTSQuery(query)
		  If safe = "" Then Return ""
		  Return String.FromArray(safe.Split(" "), " OR ")
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ExtractClassName(title As String, chunkText As String) As String
		  // Ported from XDOX Retrieval.ExtractClassName. Two title conventions
		  // coexist: MBS docset titles are "ClassName.member..." (dot) — safe to
		  // trust from the title alone. Native Xojo-doc titles use
		  // "ClassName > member..." (arrow) instead, but the same arrow shape is
		  // also used by IDE-guide/tutorial sections that aren't classes at all
		  // ("Toolbar > Common members" is the Xojo IDE's own toolbar, unrelated
		  // to the DesktopToolbar control). Trusting the arrow form from the
		  // title alone re-creates the bug this boost exists to prevent — a
		  // generic page out-ranking the real API chunk. An arrow-form candidate
		  // is only accepted when corroborated by the chunk text: either this
		  // chunk IS the class's canonical overview page ("ClassName > Overview"
		  // titles have prose bodies, checked by title suffix), or the chunk is
		  // a real member page whose body's second line repeats
		  // "ClassName.MemberName" (e.g. "DesktopHTMLViewer > Loadurl" is
		  // followed by "DesktopHTMLViewer.LoadURL") — guide/tutorial chunks
		  // never do this. Keep in sync with XDOX Retrieval.ExtractClassName.
		  Var dotPos As Integer = title.IndexOf(".")
		  Var arrowPos As Integer = title.IndexOf(" > ")
		  Var sepPos As Integer = dotPos
		  Var isArrow As Boolean = False
		  If arrowPos >= 0 And (dotPos < 0 Or arrowPos < dotPos) Then
		    sepPos = arrowPos
		    isArrow = True
		  End If
		  If sepPos < 4 Then Return ""
		  Var candidate As String = title.Left(sepPos)
		  For i As Integer = 0 To candidate.Length - 1
		    Var ch As String = candidate.Middle(i, 1)
		    Var isAlnum As Boolean = (ch >= "a" And ch <= "z") Or (ch >= "A" And ch <= "Z") Or (ch >= "0" And ch <= "9")
		    If Not isAlnum Then Return ""
		  Next

		  If isArrow Then
		    Var isOverviewTitle As Boolean = title = candidate + " > Overview"
		    Var bodyLine As String = chunkText
		    Var nl As Integer = bodyLine.IndexOf(EndOfLine)
		    If nl >= 0 Then bodyLine = bodyLine.Middle(nl + 1)
		    bodyLine = bodyLine.Trim
		    Var isMemberSignature As Boolean = bodyLine.Left(candidate.Length + 1) = candidate + "."
		    If Not isOverviewTitle And Not isMemberSignature Then Return ""
		  End If

		  Return candidate
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function TargetPlatformLabel(title As String) As String
		  // Ported from XDOX Retrieval.TargetPlatformLabel. Xojo's native-doc
		  // class names carry their target platform as a naming prefix
		  // (DesktopButton, WebPage, iOSCountdownPicker, ConsoleApplication) — a
		  // real, documented Xojo convention, not something inferred here.
		  // Confirmed live on the XDOX side: asking about showing a webpage
		  // retrieved WebPage (a Web-target server-side page class whose
		  // GotoURL/ExecuteJavaScript methods read as plausible cosine matches
		  // for "webpage") with nothing in the delivered chunk text
		  // distinguishing it from a desktop-app answer. XMCP is a general Xojo
		  // assistant tool, not Desktop-only, so excluding non-Desktop classes
		  // from results was rejected — the fix makes the target explicit in the
		  // returned text instead of hiding non-Desktop results. Only labels
		  // when a prefix is recognized, so cross-platform classes (FolderItem,
		  // String, Dictionary) are left unlabeled. Keep in sync with XDOX
		  // Retrieval.TargetPlatformLabel.
		  Var sepPos As Integer = title.IndexOf(".")
		  Var arrowPos As Integer = title.IndexOf(" > ")
		  If arrowPos >= 0 And (sepPos < 0 Or arrowPos < sepPos) Then sepPos = arrowPos
		  If sepPos < 4 Then Return ""
		  Var candidate As String = title.Left(sepPos)

		  // Exact-case prefix checks — NOT the string >=/<= operators, which are
		  // case-insensitive by default in Xojo and would otherwise make e.g.
		  // "desktopfoo" match "Desktop" too. StartsWithExact does an ordinal
		  // (Asc-based) per-character compare instead.
		  If StartsWithExact(candidate, "Desktop") Then Return "[Desktop-target class] "
		  If StartsWithExact(candidate, "iOS") Then Return "[iOS-target class] "
		  If StartsWithExact(candidate, "Console") Then Return "[Console-target class] "
		  If StartsWithExact(candidate, "Android") Then Return "[Android-target class] "
		  // "Web" alone would also match "WebService"/"WebFile" (still
		  // Web-target, fine) but must not match unrelated words that merely
		  // start with those letters — Xojo's own naming convention already
		  // guarantees a target-prefixed class name is followed by an uppercase
		  // letter (WebPage, not "Webpage"), so require that too.
		  If StartsWithExact(candidate, "Web") And candidate.Length > 3 Then
		    Var nextCode As Integer = candidate.Middle(3, 1).Asc
		    If nextCode >= 65 And nextCode <= 90 Then Return "[Web-target class — server-side web app, not desktop] "
		  End If
		  Return ""
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function StartsWithExact(s As String, prefix As String) As Boolean
		  // Case-SENSITIVE prefix check — String.Left(n) = "..." uses Xojo's
		  // default case-insensitive comparison, which would match "desktopfoo"
		  // against "Desktop" too. Xojo class names always use the documented
		  // capitalization, so an exact match is correct here.
		  If s.Length < prefix.Length Then Return False
		  Var lhs As String = s.Left(prefix.Length)
		  For i As Integer = 0 To prefix.Length - 1
		    If lhs.Middle(i, 1).Asc <> prefix.Middle(i, 1).Asc Then Return False
		  Next
		  Return True
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function QueryNamesClass(queryLower As String, classNameLower As String) As Boolean
		  // Ported from XDOX Retrieval.QueryNamesClass. A plain IndexOf substring
		  // check matches "WebView" inside "desktopwkwebviewcontrolmbs" —
		  // confirmed live on the XDOX side that asking about
		  // DesktopWKWebViewControlMBS spuriously pulled in WebView's chunks (an
		  // unrelated Xojo Web-target class) because "webview" is a literal
		  // substring of the longer class name, which then fed the model an
		  // off-topic Overview chunk it stitched into inventing a nonexistent
		  // control. Requiring word boundaries (neither the character before nor
		  // after the match may be alphanumeric) keeps the intended case — a
		  // class name appearing as its own word/token in the query — while
		  // rejecting one class name that merely happens to be a substring of
		  // another, longer one. Keep in sync with XDOX Retrieval.QueryNamesClass.
		  Var pos As Integer = queryLower.IndexOf(classNameLower)
		  While pos >= 0
		    Var beforeOk As Boolean = (pos = 0) Or Not IsAlnumChar(queryLower.Middle(pos - 1, 1))
		    Var afterPos As Integer = pos + classNameLower.Length
		    Var afterOk As Boolean = (afterPos >= queryLower.Length) Or Not IsAlnumChar(queryLower.Middle(afterPos, 1))
		    If beforeOk And afterOk Then Return True
		    pos = queryLower.IndexOf(pos + 1, classNameLower)
		  Wend
		  Return False
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function IsAlnumChar(ch As String) As Boolean
		  If ch = "" Then Return False
		  Return (ch >= "a" And ch <= "z") Or (ch >= "A" And ch <= "Z") Or (ch >= "0" And ch <= "9")
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function QueryNamesAnyClass(query As String) As Boolean
		  // Ported from XDOX Retrieval.ChunkSearchLimit's PascalCase-word
		  // heuristic (same shape as XDOX SymbolCheck.ExtractPascalCaseWords):
		  // a word starting with an uppercase letter, all alphanumeric, and
		  // containing at least one lowercase letter is treated as a class
		  // name — this rules out ALL-CAPS acronyms like "URL" or "HTML"
		  // (common English/tech words, not class names) which would
		  // otherwise widen maxResults for every query that merely mentions
		  // one. Kept as its own small check rather than reusing
		  // QueryNamesClass, which needs a specific className to test
		  // against — this only needs to know SOME class-shaped word is
		  // present, not which one.
		  For Each word As String In query.Split(" ")
		    Var w As String = word
		    While w.Length > 0 And Not IsAlnumChar(w.Left(1))
		      w = w.Middle(1)
		    Wend
		    While w.Length > 0 And Not IsAlnumChar(w.Right(1))
		      w = w.Left(w.Length - 1)
		    Wend
		    If w.Length < kMinClassWordLength Then Continue
		    // NOT w.Left(1) >= "A" And w.Left(1) <= "Z" — Xojo's string
		    // comparison operators are case-insensitive by default (see
		    // ExtractClassName's isAlnum comment for the same pitfall
		    // elsewhere in this file), which would make this match ANY
		    // starting letter, not just uppercase. .Asc gives the ordinal
		    // code point for a true case-sensitive check.
		    Var firstCode As Integer = w.Left(1).Asc
		    If firstCode < 65 Or firstCode > 90 Then Continue // must start uppercase
		    Var hasLower As Boolean = False
		    Var allAlnum As Boolean = True
		    For i As Integer = 1 To w.Length - 1
		      Var ch As String = w.Middle(i, 1)
		      If Not IsAlnumChar(ch) Then
		        allAlnum = False
		        Exit
		      End If
		      Var code As Integer = ch.Asc
		      If code >= 97 And code <= 122 Then hasLower = True
		    Next
		    If allAlnum And hasLower Then Return True
		  Next
		  Return False
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub Destructor()
		  If mDB <> Nil Then
		    mDB.Close
		    mDB = Nil
		  End If
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Available() As Boolean
		  EnsureAvailable
		  Return mAvailable
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function RerankAvailable() As Boolean
		  EnsureRerankAvailable
		  Return mRerankAvailable
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Search(query As String, maxResults As Integer) As String
		  If Not mAvailable Then Return ""
		  If mDB = Nil Then Return ""

		  // Ported from XDOX Retrieval.ChunkSearchLimit. Unlike XDOX (which
		  // called SearchChunks with a hardcoded 4), XMCP's maxResults comes
		  // from the calling LLM/agent — this only RAISES it as a floor, so
		  // an explicit caller request for more results is still honoured. A
		  // query naming a specific Xojo class (PascalCase word, e.g.
		  // "DesktopWKWebViewControlMBS") is asking about ONE class's API
		  // surface, not a broad topic — a narrow maxResults can fill up
		  // entirely with that class's own chunks (via kClassNameBoost) and
		  // still miss the one member that actually answers the question.
		  // Confirmed live on the XDOX side (see the retrieval-quality
		  // backlog): a class-named query filled all 4 default slots with a
		  // Type: event and a read-only property instead of the one real
		  // method that answered the question. MUST happen before cacheKey
		  // is built below — the cache key includes maxResults, so adjusting
		  // it after would make a search run at one limit while the cache
		  // records another.
		  If QueryNamesAnyClass(query) And maxResults < kWidenedChunkLimit Then
		    maxResults = kWidenedChunkLimit
		  End If

		  // Read fresh so a live version switch in XDOX takes effect immediately —
		  // and so the cache never serves another version's results.
		  Var activeVersion As String = ActiveDocsVersion

		  // --- Cache check (#13) ---
		  Var cacheKey As String = activeVersion + "|" + query + "|" + maxResults.ToString
		  If mCache <> Nil And mCache.HasKey(cacheKey) Then
		    Return mCache.Value(cacheKey)
		  End If

		  Var queryEmb As MemoryBlock = FetchEmbedding(query)
		  If queryEmb = Nil Then
		    // Server died since the last probe — drop to keyword tier and let the
		    // cooldown re-probe pick it back up when it returns.
		    mAvailable = False
		    mLastProbeMicros = Microseconds
		    Return ""
		  End If

		  // --- Vector search: score all embedded chunks (#12 persistent connection) ---
		  // Multi-version: restrict to the active version plus version-independent
		  // chunks (docs_version='') and MBS docset chunks (docs_version=kMBSDocsVersion);
		  // skipped on legacy DBs without the column. Keep in sync with XDOX
		  // Retrieval.HybridSearchChunks. (activeVersion read above.)
		  Var rs As RowSet
		  Try
		    If mHasChunkVersion Then
		      rs = mDB.SelectSQL("SELECT c.id, c.title, c.chunk_text, c.source, c.chunk_index, c.prev_id, c.next_id, e.embedding FROM embeddings e JOIN chunks c ON e.chunk_id = c.id WHERE c.docs_version = ? OR c.docs_version = '' OR c.docs_version = ?", activeVersion, kMBSDocsVersion)
		    Else
		      rs = mDB.SelectSQL("SELECT c.id, c.title, c.chunk_text, c.source, c.chunk_index, c.prev_id, c.next_id, e.embedding FROM embeddings e JOIN chunks c ON e.chunk_id = c.id")
		    End If
		  Catch e As DatabaseException
		    Return ""
		  End Try

		  Var chunkIDs() As Integer
		  Var titles() As String
		  Var texts() As String
		  Var sources() As String
		  Var chunkIndexes() As Integer
		  Var prevIDs() As Integer
		  Var nextIDs() As Integer
		  Var scores() As Double

		  Do Until rs.AfterLastRow
		    Var embBlob As MemoryBlock = rs.Column("embedding").BlobValue
		    If embBlob <> Nil And embBlob.Size > 0 Then
		      Var score As Double = CosineSimilarity(queryEmb, embBlob)
		      chunkIDs.Add(rs.Column("id").IntegerValue)
		      titles.Add(rs.Column("title").StringValue)
		      texts.Add(rs.Column("chunk_text").StringValue)
		      sources.Add(rs.Column("source").StringValue)
		      chunkIndexes.Add(rs.Column("chunk_index").IntegerValue)
		      prevIDs.Add(rs.Column("prev_id").IntegerValue)
		      nextIDs.Add(rs.Column("next_id").IntegerValue)
		      scores.Add(score)
		    End If
		    rs.MoveToNextRow
		  Loop
		  rs.Close

		  // --- FTS5 hybrid scoring (#1): boost vector scores with full-text rank ---
		  Var ftsScores() As Double
		  For i As Integer = 0 To chunkIDs.LastIndex
		    ftsScores.Add(0.0)
		  Next i

		  Var ftsSafe As String = BuildMatchQuery(query)
		  Try
		    Var ftsRS As RowSet
		    // ORDER BY is load-bearing, not cosmetic: BuildMatchQuery OR-joins
		    // every sanitized token, so a conversational query can MATCH tens
		    // of thousands of rows on common words alone. Without an explicit
		    // order, SQLite returns an ARBITRARY 200-row slice under LIMIT —
		    // confirmed live on the XDOX side to silently drop the actually-
		    // relevant chunks (strong true BM25 matches) while keeping
		    // irrelevant ones that merely survived the truncation, which then
		    // won the hybrid ranking because their FTS leg normalized to ~0.99
		    // while the true match's leg silently defaulted to 0.0 (never
		    // found in the truncated slice at all).
		    If ftsSafe <> "" Then ftsRS = mDB.SelectSQL( _
		      "SELECT rowid, bm25(chunks_fts) AS bm25_score FROM chunks_fts WHERE chunks_fts MATCH ? ORDER BY bm25(chunks_fts) LIMIT 200", _
		      ftsSafe)
		    If ftsRS <> Nil Then
		      // Build an ID→fts-score map by scanning results
		      Var ftsMap As New Dictionary
		      Do Until ftsRS.AfterLastRow
		        Var rid As Integer = ftsRS.Column("rowid").IntegerValue
		        // bm25() returns negative values; more negative = better match
		        Var bm25 As Double = ftsRS.Column("bm25_score").DoubleValue
		        // Normalise to [0,1]: map bm25 from (-∞,0] to [0,1] via simple sigmoid-like clamp
		        Var normScore As Double = 1.0 / (1.0 + Exp(bm25 * 0.5))
		        ftsMap.Value(rid) = normScore
		        ftsRS.MoveToNextRow
		      Loop
		      ftsRS.Close
		      // Apply FTS scores to our result array. NOT CDbl(Variant) — see
		      // SearchNotesHybrid's ftsMap fix above for why.
		      For i As Integer = 0 To chunkIDs.LastIndex
		        If ftsMap.HasKey(chunkIDs(i)) Then
		          ftsScores(i) = ftsMap.Value(chunkIDs(i)).DoubleValue
		        End If
		      Next i
		    End If
		  Catch
		    // FTS not available (old DB without chunks_fts) — vector-only mode.
		  End Try

		  // Combine: 70% vector + 30% FTS, plus a flat boost when the query names
		  // this chunk's class exactly. Ported from XDOX Retrieval.HybridSearchChunks
		  // — cosine similarity alone can't reliably separate e.g.
		  // "DesktopWKWebViewControlMBS" from "DesktopWebView2ControlMBS" (both
		  // score ~0.75 against a query naming the former), so an explicit
		  // substring match on a named class overrides a close cosine race.
		  //
		  // While scoring: also note which chunk (if any) IS the matched class's
		  // own "ClassName > Overview" page — overviewIdx, guaranteed into the
		  // results below rather than left to compete on score. Ported from XDOX
		  // Retrieval.HybridSearchChunks: kClassNameBoost applies identically to
		  // EVERY chunk of a matched class, so it gives a class's own Overview
		  // chunk no relative edge over that same class's specific member
		  // chunks — confirmed live on the XDOX side that a flat Overview-only
		  // boost on top of kClassNameBoost was still insufficient (per-chunk
		  // score spread is too wide to safely tune a constant to), so
		  // deterministic inclusion (same pattern as PinnedMigrationResults) is
		  // used instead of trying to out-tune the score race.
		  Var queryLowerForBoost As String = query.Lowercase
		  Var combinedScores() As Double
		  Var overviewIdx As Integer = -1
		  For i As Integer = 0 To scores.LastIndex
		    Var score As Double = scores(i) * 0.7 + ftsScores(i) * 0.3
		    Var className As String = ExtractClassName(titles(i), texts(i))
		    If className <> "" And QueryNamesClass(queryLowerForBoost, className.Lowercase) Then
		      score = score + kClassNameBoost
		      If overviewIdx < 0 And titles(i) = className + " > Overview" Then overviewIdx = i
		    End If
		    combinedScores.Add(score)
		  Next i

		  // --- Partial selection sort for top maxResults*2 candidates (to allow dedup) ---
		  Var candidateCount As Integer = maxResults * 2
		  If combinedScores.Count < candidateCount Then candidateCount = combinedScores.Count
		  Var used() As Boolean
		  For i As Integer = 0 To combinedScores.LastIndex
		    used.Add(False)
		  Next i

		  Var topIdxs() As Integer
		  For r As Integer = 0 To candidateCount - 1
		    Var bestIdx As Integer = -1
		    Var bestScore As Double = -2.0
		    For i As Integer = 0 To combinedScores.LastIndex
		      If Not used(i) And combinedScores(i) > bestScore Then
		        bestScore = combinedScores(i)
		        bestIdx = i
		      End If
		    Next i
		    If bestIdx < 0 Then Exit
		    used(bestIdx) = True
		    topIdxs.Add(bestIdx)
		  Next r

		  // --- Deduplication (#4): skip chunks from same source with near-identical score ---
		  // Also tracks which chunk IDs are included so neighbour expansion doesn't re-add them.
		  Var includedIDs As New Dictionary
		  Var sourceLastScore As New Dictionary
		  Var kDedupeScoreDelta As Double = 0.04

		  Var finalIdxs() As Integer
		  For Each idx As Integer In topIdxs
		    If finalIdxs.Count >= maxResults Then Exit
		    Var src As String = sources(idx)
		    Var sc As Double = combinedScores(idx)
		    If sourceLastScore.HasKey(src) Then
		      // NOT CDbl(Variant) — see the ftsMap fixes above for why.
		      Var prevScore As Double = sourceLastScore.Value(src).DoubleValue
		      // Keep the chunk only if it adds meaningfully different content from the same source.
		      If Abs(sc - prevScore) < kDedupeScoreDelta Then Continue
		    End If
		    sourceLastScore.Value(src) = sc
		    includedIDs.Value(chunkIDs(idx)) = True
		    finalIdxs.Add(idx)
		  Next

		  // Guarantee the matched class's own Overview chunk survives into
		  // finalIdxs even if it lost the score race above — see the comment on
		  // overviewIdx. If it's not already in (the common case — that's the
		  // bug this exists to fix), bump the weakest current slot rather than
		  // growing past maxResults. Ported from XDOX Retrieval.HybridSearchChunks.
		  If overviewIdx >= 0 And Not includedIDs.HasKey(chunkIDs(overviewIdx)) Then
		    If finalIdxs.Count < maxResults Then
		      finalIdxs.Add(overviewIdx)
		    Else
		      Var weakestPos As Integer = 0
		      For p As Integer = 1 To finalIdxs.LastIndex
		        If combinedScores(finalIdxs(p)) < combinedScores(finalIdxs(weakestPos)) Then weakestPos = p
		      Next
		      finalIdxs(weakestPos) = overviewIdx
		    End If
		    includedIDs.Value(chunkIDs(overviewIdx)) = True
		  End If

		  // --- Reranking: ported from XDOX Retrieval.HybridSearchChunks ---
		  // A cross-encoder pass over the already-selected candidates that
		  // reorders by real query-document relevance instead of trusting
		  // cosine+BM25 alone. XMCP does NOT hard-gate on this the way XDOX's
		  // chat UI does (never withholds results outright) — an LLM caller may
		  // legitimately want to see low-relevance candidates and judge them
		  // itself. But it DOES surface the best score explicitly in the
		  // response header below: a raw chunk dump with no confidence signal
		  // has the same failure mode XDOX's chat model had (nothing
		  // distinguishes "good match" from "best of a bad set"), and the
		  // caller burns tokens/risks synthesizing a wrong answer from
		  // marginally-relevant chunks exactly like XDOX did before this was
		  // fixed. Pure fallback if the reranker is down or was never
		  // installed (XDOX owns its lifecycle, not XMCP): finalIdxs keeps its
		  // existing cosine+BM25 order and bestRerankScore stays -1 (no line
		  // added to the header).
		  Var bestRerankScore As Double = -1.0
		  EnsureRerankAvailable
		  If mRerankAvailable And finalIdxs.Count > 0 Then
		    Var candidateTexts() As String
		    For Each idx As Integer In finalIdxs
		      candidateTexts.Add(texts(idx))
		    Next
		    Var rerankScores() As Double = FetchRerankScores(query, candidateTexts)
		    If rerankScores.Count = 0 Then
		      // Server died since the last probe — drop the tier and let the
		      // cooldown re-probe pick it back up when it returns.
		      mRerankAvailable = False
		      mLastRerankProbeMicros = Microseconds
		    ElseIf rerankScores.Count = finalIdxs.Count Then
		      // Pair each finalIdxs slot with its rerank score, then sort
		      // descending — a small array (<= maxResults*2), insertion sort is
		      // plenty and keeps this dependency-free.
		      Var order() As Integer
		      For i As Integer = 0 To finalIdxs.LastIndex
		        order.Add(i)
		      Next i
		      For i As Integer = 1 To order.LastIndex
		        Var key As Integer = order(i)
		        Var keyScore As Double = rerankScores(key)
		        Var j As Integer = i - 1
		        While j >= 0 And rerankScores(order(j)) < keyScore
		          order(j + 1) = order(j)
		          j = j - 1
		        Wend
		        order(j + 1) = key
		      Next i
		      Var rerankedIdxs() As Integer
		      Var bestScore As Double = -2.0
		      For Each pos As Integer In order
		        rerankedIdxs.Add(finalIdxs(pos))
		        If rerankScores(pos) > bestScore Then bestScore = rerankScores(pos)
		      Next
		      finalIdxs = rerankedIdxs
		      bestRerankScore = bestScore
		    End If
		  End If

		  // --- Neighbour expansion (#6): for high-score chunks, pull adjacent chunks ---
		  Var kNeighbourThreshold As Double = 0.72
		  Var neighbourIdxs() As Integer  // indices into the original arrays for neighbour chunks

		  For Each idx As Integer In finalIdxs
		    If scores(idx) < kNeighbourThreshold Then Continue
		    // Fetch prev chunk if not already included
		    Var pID As Integer = prevIDs(idx)
		    If pID > 0 And Not includedIDs.HasKey(pID) Then
		      Var nChunk As RowSet = FetchChunkByID(pID)
		      If nChunk <> Nil Then
		        includedIDs.Value(pID) = True
		        chunkIDs.Add(pID)
		        titles.Add(nChunk.Column("title").StringValue)
		        texts.Add(nChunk.Column("chunk_text").StringValue)
		        sources.Add(nChunk.Column("source").StringValue)
		        chunkIndexes.Add(nChunk.Column("chunk_index").IntegerValue)
		        prevIDs.Add(nChunk.Column("prev_id").IntegerValue)
		        nextIDs.Add(nChunk.Column("next_id").IntegerValue)
		        nChunk.Close
		        neighbourIdxs.Add(chunkIDs.LastIndex)
		      End If
		    End If
		    // Fetch next chunk if not already included
		    Var nID As Integer = nextIDs(idx)
		    If nID > 0 And Not includedIDs.HasKey(nID) Then
		      Var nChunk As RowSet = FetchChunkByID(nID)
		      If nChunk <> Nil Then
		        includedIDs.Value(nID) = True
		        chunkIDs.Add(nID)
		        titles.Add(nChunk.Column("title").StringValue)
		        texts.Add(nChunk.Column("chunk_text").StringValue)
		        sources.Add(nChunk.Column("source").StringValue)
		        chunkIndexes.Add(nChunk.Column("chunk_index").IntegerValue)
		        prevIDs.Add(nChunk.Column("prev_id").IntegerValue)
		        nextIDs.Add(nChunk.Column("next_id").IntegerValue)
		        nChunk.Close
		        neighbourIdxs.Add(chunkIDs.LastIndex)
		      End If
		    End If
		  Next

		  // --- Logical sorting (#9): group by source, sort groups by best combined score,
		  //     sort chunks within each group by chunk_index ---
		  // Build: source → list of (chunk_index, title, text, isNeighbour)
		  Var sourceOrder() As String          // source names in score order
		  Var sourceSeen As New Dictionary
		  // First pass: add sources from finalIdxs (ordered by combined score)
		  For Each idx As Integer In finalIdxs
		    Var src As String = sources(idx)
		    If Not sourceSeen.HasKey(src) Then
		      sourceSeen.Value(src) = True
		      sourceOrder.Add(src)
		    End If
		  Next
		  // Also add sources from neighbour chunks (they share source with a finalIdx entry,
		  // so they'll already be in sourceOrder — no new sources from neighbours).

		  // Build per-source chunk lists: (chunk_index, arrayIndex)
		  Var sourceChunks As New Dictionary
		  // Populate from finalIdxs
		  For Each idx As Integer In finalIdxs
		    Var src As String = sources(idx)
		    If Not sourceChunks.HasKey(src) Then
		      sourceChunks.Value(src) = New Dictionary
		    End If
		    Var srcMap As Dictionary = sourceChunks.Value(src)
		    srcMap.Value(chunkIndexes(idx)) = idx
		  Next
		  // Populate from neighbourIdxs
		  For Each idx As Integer In neighbourIdxs
		    Var src As String = sources(idx)
		    If Not sourceChunks.HasKey(src) Then
		      sourceChunks.Value(src) = New Dictionary
		    End If
		    Var srcMap As Dictionary = sourceChunks.Value(src)
		    srcMap.Value(chunkIndexes(idx)) = idx
		  Next

		  // Render results
		  Var results() As String
		  Var anyPlatformLabel As Boolean = False
		  For Each src As String In sourceOrder
		    If Not sourceChunks.HasKey(src) Then Continue
		    Var srcMap As Dictionary = sourceChunks.Value(src)
		    // Sort chunk_index values ascending
		    Var idxKeys() As Integer
		    For Each k As Variant In srcMap.Keys
		      idxKeys.Add(k.IntegerValue)
		    Next
		    // Simple insertion sort (small list)
		    For si As Integer = 1 To idxKeys.LastIndex
		      Var key As Integer = idxKeys(si)
		      Var sj As Integer = si - 1
		      While sj >= 0 And idxKeys(sj) > key
		        idxKeys(sj + 1) = idxKeys(sj)
		        sj = sj - 1
		      Wend
		      idxKeys(sj + 1) = key
		    Next si

		    For Each cidx As Integer In idxKeys
		      Var ai As Integer = srcMap.Value(cidx)
		      Var platformLabel As String = TargetPlatformLabel(titles(ai))
		      If platformLabel <> "" Then anyPlatformLabel = True
		      results.Add("--- " + titles(ai) + " ---" + EndOfLine + platformLabel + texts(ai))
		    Next
		  Next

		  If results.Count = 0 Then Return ""

		  Var header As String = "Found " + results.Count.ToString + " result(s) for """ + query + """ (semantic"
		  Var headerVersion As String = If(activeVersion <> "", activeVersion, mDocsVersion)
		  If headerVersion <> "" Then header = header + ", " + headerVersion
		  header = header + "):"
		  // Surface the reranker's confidence explicitly rather than silently
		  // returning a raw chunk dump — same threshold as XDOX's
		  // Reranker.kNoMatchThreshold, kept in sync manually (no shared
		  // constant between the two apps). bestRerankScore stays -1 when no
		  // rerank signal is available (server down/not installed), in which
		  // case this line is omitted entirely rather than claiming low
		  // confidence it can't actually measure.
		  If bestRerankScore >= 0.0 And bestRerankScore < 0.9 Then
		    header = header + EndOfLine + "Note: none of these results closely match the query (reranker confidence " _
		      + Format(bestRerankScore, "0.00") + ") — verify before treating them as confirming this feature exists."
		  End If
		  // Xojo targets multiple platforms (Desktop, Web, iOS, Console, Android)
		  // with different, incompatible class libraries. A class tagged
		  // "[Web-target class]" etc. below only exists for that platform — a
		  // result being present does NOT mean the feature is available on
		  // whatever platform the caller's user actually asked about. Ported
		  // from XDOX's system-prompt rule (XDOXSession.ClosingReminders):
		  // confirmed live there that without an explicit instruction, a model
		  // reading a Web-target chunk answered a desktop-app question with an
		  // unqualified "Yes" and then contradicted itself, or invented a
		  // plausible-sounding desktop class name that doesn't exist.
		  If anyPlatformLabel Then
		    header = header + EndOfLine + "Note: one or more results below are tagged with their Xojo target " _
		      + "platform — do not treat a result for one platform (e.g. Web-target) as confirming the same " _
		      + "feature exists on a different platform (e.g. Desktop) the caller may actually be asking about."
		  End If
		  Var output As String = header + _
		    EndOfLine + EndOfLine + String.FromArray(results, EndOfLine + EndOfLine)

		  // Store in cache (#13)
		  If mCache = Nil Then mCache = New Dictionary
		  If mCache.Count >= kCacheMaxEntries Then
		    // Simple eviction: clear the whole cache when full.
		    mCache = New Dictionary
		  End If
		  mCache.Value(cacheKey) = output

		  Return output

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function FetchChunkByID(id As Integer) As RowSet
		  If mDB = Nil Then Return Nil
		  Try
		    Var rs As RowSet = mDB.SelectSQL( _
		      "SELECT title, chunk_text, source, chunk_index, prev_id, next_id FROM chunks WHERE id = ?", id)
		    If rs = Nil Or rs.AfterLastRow Then Return Nil
		    Return rs
		  Catch e As DatabaseException
		    Return Nil
		  End Try
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function FetchEmbedding(text As String, timeoutMs As Integer = 10000) As MemoryBlock
		  // nomic-embed-text-v1.5 requires its "search_query: " task-instruction
		  // prefix for asymmetric retrieval — every call here is query-time (XMCP
		  // never indexes; XDOX's indexer prefixes chunk/note text with
		  // "search_document: " on its side, per Embedder.kTaskPrefixDocument).
		  // Keep this prefix in sync with XDOX's Embedder.kTaskPrefixQuery.
		  Var escapedText As String = EscapeJSON("search_query: " + text)
		  Var body As String = "{""model"":""nomic-embed-text.gguf"",""input"":""" + escapedText + """}"

		  mHttpDone = False
		  mHttpBody = ""
		  mHttpStatus = 0

		  Var http As New URLConnection
		  AddHandler http.ContentReceived, AddressOf HttpContentReceived
		  AddHandler http.Error, AddressOf HttpError
		  http.RequestHeader("Content-Type") = "application/json"
		  http.SetRequestContent(body, "application/json")

		  Try
		    http.Send("POST", mEmbeddingUrl)
		  Catch e As RuntimeException
		    Return Nil
		  End Try

		  Var timeout As Integer = 0
		  While Not mHttpDone And timeout < timeoutMs
		    App.DoEvents(10)
		    timeout = timeout + 10
		  Wend

		  If Not mHttpDone Or mHttpStatus <> 200 Then Return Nil

		  Return ParseEmbeddingJSON(mHttpBody)

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function FetchRerankScores(query As String, candidates() As String, timeoutMs As Integer = 10000) As Double()
		  // POST /v1/rerank on XDOX's reranker server (port 8093, XDOX-managed —
		  // same relationship as the embedding server on 8089). Mirrors XDOX's
		  // Reranker.RerankBatch: one relevance score per candidate, empty array
		  // on any failure so the caller degrades to its existing ranking rather
		  // than treating "reranker down" as a hard error.
		  Var result() As Double
		  If candidates.Count = 0 Then Return result

		  Var body As New JSONItem
		  body.Value("model") = "qwen3-reranker-0.6b.gguf"
		  body.Value("query") = query
		  Var docs As New JSONItem
		  For Each c As String In candidates
		    docs.Add(c)
		  Next
		  body.Value("documents") = docs

		  mHttpDone = False
		  mHttpBody = ""
		  mHttpStatus = 0

		  Var http As New URLConnection
		  AddHandler http.ContentReceived, AddressOf HttpContentReceived
		  AddHandler http.Error, AddressOf HttpError
		  http.RequestHeader("Content-Type") = "application/json"
		  http.SetRequestContent(body.ToString, "application/json")

		  Try
		    http.Send("POST", mRerankUrl)
		  Catch e As RuntimeException
		    Return result
		  End Try

		  Var timeout As Integer = 0
		  While Not mHttpDone And timeout < timeoutMs
		    App.DoEvents(10)
		    timeout = timeout + 10
		  Wend

		  If Not mHttpDone Or mHttpStatus <> 200 Then Return result

		  Return ParseRerankJSON(mHttpBody, candidates.Count)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ParseRerankJSON(json As String, expectedCount As Integer) As Double()
		  // Response: {"results":[{"index":0,"relevance_score":0.97},...]} — same
		  // defensive, index-keyed parse as XDOX's Reranker.ParseRerankResponse.
		  Var result() As Double
		  Try
		    Var root As New JSONItem(json)
		    If Not root.HasKey("results") Then Return result
		    Var resultsArray As JSONItem = root.Child("results")
		    If resultsArray = Nil Or resultsArray.Count = 0 Then Return result

		    result.ResizeTo(expectedCount - 1)
		    For i As Integer = 0 To expectedCount - 1
		      result(i) = 0.0
		    Next i

		    For d As Integer = 0 To resultsArray.Count - 1
		      Var item As JSONItem = resultsArray.ChildAt(d)
		      If Not item.HasKey("relevance_score") Then Continue

		      Var idx As Integer = d
		      If item.HasKey("index") Then idx = item.Value("index").IntegerValue
		      If idx < 0 Or idx > result.LastIndex Then Continue

		      result(idx) = item.Value("relevance_score").DoubleValue
		    Next d
		  Catch e As RuntimeException
		    Return result
		  End Try
		  Return result
		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub HttpError(sender As URLConnection, err As RuntimeException)
		  #Pragma Unused sender
		  #Pragma Unused err
		  // Connection refused (server down) — fail fast instead of waiting out
		  // the full poll window.
		  mHttpStatus = 0
		  mHttpDone = True
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Sub HttpContentReceived(sender As URLConnection, url As String, httpStatus As Integer, content As String)
		  #Pragma Unused sender
		  #Pragma Unused url
		  mHttpStatus = httpStatus
		  mHttpBody = content.DefineEncoding(Encodings.UTF8)
		  mHttpDone = True

		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function ParseEmbeddingJSON(json As String) As MemoryBlock
		  Var root As JSONItem
		  Try
		    root = New JSONItem(json)
		  Catch e As JSONException
		    Return Nil
		  End Try

		  If Not root.HasKey("data") Then Return Nil
		  Var dataArr As JSONItem = root.Child("data")
		  If dataArr = Nil Or dataArr.Count = 0 Then Return Nil
		  Var firstItem As JSONItem = dataArr.ChildAt(0)
		  If Not firstItem.HasKey("embedding") Then Return Nil
		  Var embArr As JSONItem = firstItem.Child("embedding")
		  Var floatCount As Integer = embArr.Count
		  If floatCount = 0 Then Return Nil

		  Var mb As New MemoryBlock(floatCount * 4)
		  mb.LittleEndian = True
		  For i As Integer = 0 To floatCount - 1
		    mb.SingleValue(i * 4) = CDbl(embArr.ValueAt(i))
		  Next i

		  Return mb

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function CosineSimilarity(a As MemoryBlock, b As MemoryBlock) As Double
		  If a = Nil Or b = Nil Then Return 0
		  Var count As Integer = a.Size / 4
		  If b.Size / 4 < count Then count = b.Size / 4

		  Var dot As Double = 0
		  Var na As Double = 0
		  Var nb As Double = 0
		  For i As Integer = 0 To count - 1
		    Var ai As Double = a.SingleValue(i * 4)
		    Var bi As Double = b.SingleValue(i * 4)
		    dot = dot + ai * bi
		    na = na + ai * ai
		    nb = nb + bi * bi
		  Next i

		  If na = 0 Or nb = 0 Then Return 0
		  Return dot / (Sqrt(na) * Sqrt(nb))

		End Function
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function EscapeJSON(s As String) As String
		  Var result As String = s
		  result = result.ReplaceAll("\", "\\")
		  result = result.ReplaceAll("""", "\""")
		  result = result.ReplaceAll(Chr(8), "\b")
		  result = result.ReplaceAll(Chr(9), "\t")
		  result = result.ReplaceAll(Chr(10), "\n")
		  result = result.ReplaceAll(Chr(12), "\f")
		  result = result.ReplaceAll(Chr(13), "\r")
		  Return result

		End Function
	#tag EndMethod


	#tag Property, Flags = &h21
		Private mAvailable As Boolean
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mRerankAvailable As Boolean
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mEmbeddingUrl As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mRerankUrl As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mDbPath As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mDocsVersion As String
	#tag EndProperty

	// True when chunks.docs_version exists (XDOX schema v3+); gates the docs
	// version filter so legacy DBs without the column still search.
	#tag Property, Flags = &h21
		Private mHasChunkVersion As Boolean
	#tag EndProperty

	// True when notes.scope exists (XDOX schema v3+); gates the scope-aware
	// outdated-label logic in note search.
	#tag Property, Flags = &h21
		Private mHasNoteScope As Boolean
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mEmbeddingDim As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mHasDatabase As Boolean
	#tag EndProperty

	// Persistent connection held open for the process lifetime (#12).
	#tag Property, Flags = &h21
		Private mDB As SQLiteDatabase
	#tag EndProperty

	// In-memory query cache: cacheKey → result string (#13).
	#tag Property, Flags = &h21
		Private mCache As Dictionary
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mHttpDone As Boolean
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mHttpBody As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mHttpStatus As Integer
	#tag EndProperty

	// Microseconds timestamp of the last (failed) embedding-server probe.
	#tag Property, Flags = &h21
		Private mLastProbeMicros As Double
	#tag EndProperty

	// Microseconds timestamp of the last (failed) reranker-server probe.
	#tag Property, Flags = &h21
		Private mLastRerankProbeMicros As Double
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mDimWarned As Boolean
	#tag EndProperty

	// Maximum number of cached query results before the cache is cleared.
	#tag Constant, Name = kCacheMaxEntries, Type = Integer, Dynamic = False, Default = \"50", Scope = Private
	#tag EndConstant

	// Cosine score threshold above which neighbour chunks are fetched (#6).
	#tag Constant, Name = kNeighbourThreshold, Type = Double, Dynamic = False, Default = \"0.72", Scope = Private
	#tag EndConstant

	// Minimum combined score for a note to be returned (matches XDOX).
	#tag Constant, Name = kNoteRelevanceFloor, Type = Double, Dynamic = False, Default = \"0.45", Scope = Private
	#tag EndConstant

	// Flat score boost when the query names a chunk's class exactly (matches XDOX).
	#tag Constant, Name = kClassNameBoost, Type = Double, Dynamic = False, Default = \"0.15", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kWidenedChunkLimit, Type = Double, Dynamic = False, Default = \"7", Scope = Private
	#tag EndConstant

	#tag Constant, Name = kMinClassWordLength, Type = Double, Dynamic = False, Default = \"4", Scope = Private
	#tag EndConstant

	// Re-probe a down embedding server at most this often (30 s).
	#tag Constant, Name = kProbeCooldownMicros, Type = Double, Dynamic = False, Default = \"30000000", Scope = Private
	#tag EndConstant

	// docs_version sentinel for MBS docset chunks — always included in results
	// regardless of active Xojo version. Must match XDOX's DBHelper.kMBSDocsVersion.
	#tag Constant, Name = kMBSDocsVersion, Type = String, Dynamic = False, Default = \"mbs", Scope = Private
	#tag EndConstant


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
