#tag Class
Protected Class MyClass
	#tag Method, Flags = &h0
		Sub Constructor(itemName As String)
		  mName = itemName
		  mCount = 0
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Function Greet() As String
		  Return "Hello from " + mName
		End Function
	#tag EndMethod

	#tag Method, Flags = &h0
		Sub IncrementCount()
		  mCount = mCount + 1
		  RaiseEvent CountChanged(mCount)
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h0
		Shared Function Create(itemName As String) As MyClass
		  // Shared (class-level) factory method — called as MyClass.Create("foo")
		  // Flags = &h0 (Public). Add "Private " prefix + keep &h0 for Private Shared,
		  // or use &h1 for Protected Shared.
		  Return New MyClass(itemName)
		End Function
	#tag EndMethod

	#tag Method, Flags = &h1
		Protected Sub InternalHelper()
		  // Protected — visible to subclasses, not to callers outside the hierarchy
		End Sub
	#tag EndMethod

	#tag Method, Flags = &h21
		Private Function FormatName() As String
		  // Private — not visible outside this class
		  Return mName.Uppercase
		End Function
	#tag EndMethod


	#tag Hook, Flags = &h0
		Event CountChanged(newCount As Integer)
	#tag EndHook


	#tag Property, Flags = &h0
		MyProperty As Integer
	#tag EndProperty

	#tag Property, Flags = &h1
		Protected ProtectedProp As String
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mCount As Integer
	#tag EndProperty

	#tag Property, Flags = &h21
		Private mName As String
	#tag EndProperty

	#tag Constant, Name = kMaxItems, Type = Integer, Dynamic = False, Default = \"100", Scope = Public
	#tag EndConstant

	#tag Note, Name = DesignNotes
		MyClass demonstrates the standard block layout for a Xojo class file.

		Block ordering within a .xojo_code file (must be preserved exactly):
		  1. #tag Method blocks       (Constructor first, then others)
		  2. #tag Hook blocks         (custom events this class fires — the IDE
		     writes a custom event definition as #tag Hook, not #tag Event;
		     #tag Event is used only for overriding an INHERITED event)
		  3. #tag Property blocks
		  4. #tag Constant blocks
		  5. #tag ViewBehavior        (always last — do not add anything after it)
		#tag Note blocks may appear anywhere after Method (confirmed by direct
		IDE testing — Xojo does not enforce a fixed position for Note).

		Access modifier flags (used on both Method and Property tags):
		  &h0   Public
		  &h1   Protected
		  &h21  Private
		The modifier keyword in the declaration line ("Protected", "Private") must
		match the flag value — both are required.

		Shared methods: add the "Shared " keyword before "Function" or "Sub".
		The flag value is the same as for instance methods (&h0 / &h1 / &h21).

		Constants use a different format from methods and properties — all
		metadata is on the #tag Constant line itself, nothing inside the block:
		  #tag Constant, Name = kMax, Type = Integer, Dynamic = False, Default = \"100", Scope = Public
		  #tag EndConstant
		Valid Scope values: Public, Protected, Private.
		Valid Type values: String, Integer, Double, Boolean, Color.
		The Default value's opening quote must always be escaped as \" — even
		for a value with nothing else to escape. A raw, unescaped opening quote
		compiles without error but silently drops the value's first character
		when Xojo reads it back.

		Custom events: a #tag Hook block inside a class body defines an event
		that the class can RaiseEvent. Consumers add an event handler with
		AddEventImplementation in the IDE or by editing the .xojo_window file.
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
			Name="mName"
			Visible=false
			Group="Behavior"
			InitialValue=""
			Type="Integer"
			EditorType=""
		#tag EndViewProperty
	#tag EndViewBehavior
End Class
#tag EndClass
