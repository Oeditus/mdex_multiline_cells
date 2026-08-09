defmodule MdexMultilineCells.PreprocessorTest do
  use ExUnit.Case, async: true

  alias MdexMultilineCells.Preprocessor

  describe "preprocess/2 with backslash continuations" do
    test "joins lines ending with backslash into single table row" do
      input = """
      | Col 1 | Col 2 |
      | --- | --- |
      | Line 1 \\
      Line 2 | Val 2 |
      """

      expected = """
      | Col 1 | Col 2 |
      | --- | --- |
      | Line 1 <br>Line 2 | Val 2 |
      """

      assert String.trim(Preprocessor.preprocess(input)) == String.trim(expected)
    end

    test "respects continuation_syntax: :backslash option" do
      input = """
      | Col 1 | Col 2 |
      | --- | --- |
      | Line 1 \\
      Line 2 | Val 2 |
      | Cell 1 | First line
        Second line |
      """

      processed = Preprocessor.preprocess(input, continuation_syntax: :backslash)

      assert processed =~ "| Line 1 <br>Line 2 | Val 2 |"
      assert processed =~ "| Cell 1 | First line"
    end
  end

  describe "preprocess/2 with unclosed multiline table rows" do
    test "joins unclosed indented cell lines" do
      input = """
      | Name | Description |
      | --- | --- |
      | Cell 1 | First line of description
        Second line of description |
      | Cell 2 | Normal row |
      """

      expected = """
      | Name | Description |
      | --- | --- |
      | Cell 1 | First line of description<br>Second line of description |
      | Cell 2 | Normal row |
      """

      assert String.trim(Preprocessor.preprocess(input)) == String.trim(expected)
    end

    test "respects continuation_syntax: :unclosed option" do
      input = """
      | Name | Description |
      | --- | --- |
      | Cell 1 | First line of description
        Second line of description |
      """

      processed = Preprocessor.preprocess(input, continuation_syntax: :unclosed)

      assert processed =~ "| Cell 1 | First line of description<br>Second line of description |"
    end
  end

  describe "preprocess/2 with key_column option" do
    test "uses specified key column index for multiline guessing" do
      input = """
      | ID | Status | Description |
      | --- | --- | --- |
      | Task 1 | Active | Line 1 |
      | Task 2 | | Line 2 of Task 2 |
      """

      # Setting key_column: 1 means check 2nd column ("Status") for empty key continuation
      processed = Preprocessor.preprocess(input, guess_multiline: true, key_column: 1)

      assert processed =~ "| Task 1<br>Task 2 | Active | Line 1<br>Line 2 of Task 2 |"
    end
  end

  describe "preprocess/2 with strip_indentation: false" do
    test "preserves leading whitespace when strip_indentation is false" do
      input = """
      | Col 1 | Col 2 |
      | --- | --- |
      | Line 1 \\
        Line 2 | Val 2 |
      """

      processed = Preprocessor.preprocess(input, strip_indentation: false)

      assert processed =~ "Line 1 <br>  Line 2"
    end
  end

  describe "preprocess/2 code block protection" do
    test "does not modify pipe lines inside fenced code blocks" do
      input = """
      # Guide

      ```elixir
      | not | table |
      | --- | --- |
      | line 1 \\
      line 2 |
      ```

      | Real | Table |
      | --- | --- |
      | line 1 \\
      line 2 | ok |
      """

      processed = Preprocessor.preprocess(input)

      assert processed =~ "```elixir\n| not | table |\n| --- | --- |\n| line 1 \\\nline 2 |\n```"
      assert processed =~ "| Real | Table |\n| --- | --- |\n| line 1 <br>line 2 | ok |"
    end
  end
end
