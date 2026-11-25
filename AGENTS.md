# Swift formatting

- Use two spaces for block indentation.
- Align wrapped parameters and arguments with the first parameter or argument,
  following `Sources/Rundown/TestHook.swift`. Put the first argument after the
  opening parenthesis and the closing parenthesis after the last argument.
- Keep multiline string literals and macro snapshots intact; their opening
  delimiters may remain on a separate line.
- Put `else` on a new line, aligned with its `guard` or `if`, including `else if`.
- Preserve unrelated formatting when making a focused change.

# Test descriptions

- Write `it`, `fIt`, and `xIt` messages as verb phrases that complete
  "it …" and state the expected behavior, such as `it("runs unfocused siblings")`.
