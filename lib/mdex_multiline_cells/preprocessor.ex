defmodule MdexMultilineCells.Preprocessor do
  @moduledoc false

  _ = """
  Preprocesses Markdown source text to support multi-line table rows.

  Normalizes multi-line table cell syntax into standard single-line Markdown table rows
  with `<br>` line break markers inside cell contents.
  """

  @doc """
  Preprocesses raw Markdown text before it is parsed into AST by MDEx.
  """
  def preprocess(markdown, opts \\ []) when is_binary(markdown) do
    continuation_syntax = Keyword.get(opts, :continuation_syntax, :all)
    strip_indentation = Keyword.get(opts, :strip_indentation, true)
    guess_multiline = Keyword.get(opts, :guess_multiline, true)
    key_column = Keyword.get(opts, :key_column, 0)

    lines = String.split(markdown, ~r/\r?\n/)

    {processed_lines, _state} =
      Enum.reduce(lines, {[], :out_of_table}, fn line, {acc, state} ->
        process_line(
          line,
          acc,
          state,
          continuation_syntax,
          strip_indentation,
          guess_multiline,
          key_column
        )
      end)

    processed_lines
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp process_line(line, acc, {:in_code_block, fence}, _syntax, _strip_indent, _guess, _key_col) do
    trimmed = String.trim(line)

    if String.starts_with?(trimmed, fence) do
      {[line | acc], :out_of_table}
    else
      {[line | acc], {:in_code_block, fence}}
    end
  end

  defp process_line(line, acc, :out_of_table, _syntax, _strip_indent, _guess, _key_col) do
    trimmed = String.trim(line)

    cond do
      fence = code_fence_start(trimmed) ->
        {[line | acc], {:in_code_block, fence}}

      table_line?(line) ->
        mode = detect_border_mode(line)
        cells = parse_row_cells(line, mode)
        formatted = format_row_cells(cells)
        pipes = count_pipes(formatted)
        {[formatted | acc], {:in_table, pipes, mode, length(cells)}}

      true ->
        {[line | acc], :out_of_table}
    end
  end

  defp process_line(
         line,
         acc,
         {:in_table, expected_pipes, mode, expected_cols},
         syntax,
         strip_indent,
         guess_multiline,
         key_column
       ) do
    trimmed = String.trim(line)

    cond do
      fence = code_fence_start(trimmed) ->
        {[line | acc], {:in_code_block, fence}}

      trimmed == "" ->
        {[line | acc], :out_of_table}

      empty_key_continuation?(acc, line, mode, guess_multiline, key_column) ->
        join_empty_key_row(line, acc, expected_pipes, mode)

      backslash_continuation?(acc, syntax) ->
        join_backslash_continuation(
          line,
          acc,
          expected_pipes,
          strip_indent,
          mode,
          expected_cols
        )

      unclosed_continuation?(acc, line, syntax, mode, expected_cols) ->
        join_unclosed_continuation(
          line,
          acc,
          expected_pipes,
          strip_indent,
          mode,
          expected_cols
        )

      table_line?(line) ->
        cells = parse_row_cells(line, mode)
        formatted = format_row_cells(cells)
        pipes = count_pipes(formatted)
        {[formatted | acc], {:in_table, max(expected_pipes, pipes), mode, length(cells)}}

      true ->
        {[line | acc], :out_of_table}
    end
  end

  defp detect_border_mode(line) do
    trimmed = String.trim(line)

    if String.starts_with?(trimmed, "|") and String.ends_with?(trimmed, "|") do
      :bordered
    else
      :borderless
    end
  end

  defp parse_row_cells(line, :bordered) do
    line
    |> String.trim()
    |> String.trim_leading("|")
    |> String.trim_trailing("|")
    |> String.split(~r/(?<!\\)\|/)
    |> Enum.map(&String.trim/1)
  end

  defp parse_row_cells(line, :borderless) do
    line
    |> String.split(~r/(?<!\\)\|/)
    |> Enum.map(&String.trim/1)
  end

  defp format_row_cells(cells) do
    converted_cells = Enum.map(cells, &convert_inline_double_backslashes/1)
    "| " <> Enum.join(converted_cells, " | ") <> " |"
  end

  defp empty_key_continuation?(acc, line, mode, true, key_column) when acc != [] do
    empty_key_row?(line, hd(acc), mode, key_column)
  end

  defp empty_key_continuation?(_acc, _line, _mode, _guess, _key_col), do: false

  defp backslash_continuation?(acc, syntax) when acc != [] and syntax in [:all, :backslash] do
    prev = hd(acc)
    not delimiter_line?(prev) and has_trailing_backslash?(prev)
  end

  defp backslash_continuation?(_acc, _syntax), do: false

  defp unclosed_continuation?(acc, line, syntax, mode, expected_cols)
       when acc != [] and syntax in [:all, :unclosed] do
    prev = hd(acc)

    not delimiter_line?(prev) and not delimiter_line?(line) and
      unclosed_row?(line, mode, expected_cols)
  end

  defp unclosed_continuation?(_acc, _line, _syntax, _mode, _expected), do: false

  defp join_empty_key_row(line, acc, expected_pipes, mode) do
    [prev | rest] = acc
    merged = merge_cell_by_cell(prev, line, mode)
    new_pipes = count_pipes(merged)
    {[merged | rest], {:in_table, max(expected_pipes, new_pipes), mode, count_cells(merged)}}
  end

  defp join_backslash_continuation(
         line,
         acc,
         expected_pipes,
         strip_indent,
         mode,
         expected_cols
       ) do
    [prev | rest] = acc
    next_part = if strip_indent, do: String.trim_leading(line), else: line

    joined =
      merge_smart_continuation(prev, next_part, expected_cols, mode)

    new_pipes = count_pipes(joined)
    {[joined | rest], {:in_table, max(expected_pipes, new_pipes), mode, expected_cols}}
  end

  defp join_unclosed_continuation(
         line,
         acc,
         expected_pipes,
         strip_indent,
         mode,
         expected_cols
       ) do
    [prev | rest] = acc
    next_part = if strip_indent, do: String.trim_leading(line), else: line

    joined =
      merge_smart_continuation(prev, next_part, expected_cols, mode)

    new_pipes = count_pipes(joined)
    {[joined | rest], {:in_table, max(expected_pipes, new_pipes), mode, expected_cols}}
  end

  defp merge_smart_continuation(prev_line, next_line, expected_cols, mode) do
    cells = parse_row_cells(next_line, mode)

    if length(cells) == expected_cols do
      merge_cell_by_cell(prev_line, cells, mode)
    else
      append_text_to_last_cell(prev_line, next_line)
    end
  end

  defp append_text_to_last_cell(prev_line, next_line) do
    cleaned_next = String.trim_trailing(String.replace(next_line, ~r/\|\s*$/, ""))
    c_converted = convert_inline_double_backslashes(cleaned_next)
    prev_cells = parse_row_cells(prev_line, :bordered)

    do_append_last_cell(prev_cells, c_converted)
  end

  defp do_append_last_cell([], c_converted), do: c_converted

  defp do_append_last_cell(prev_cells, c_converted) do
    last_idx = length(prev_cells) - 1

    updated_cells =
      List.update_at(prev_cells, last_idx, fn old ->
        clean_old = String.replace(String.trim(old), ~r/\\$/, "")

        cond do
          clean_old != "" and String.trim(c_converted) != "" ->
            clean_old <> "<br>" <> c_converted

          clean_old != "" ->
            clean_old

          true ->
            c_converted
        end
      end)

    format_row_cells(updated_cells)
  end

  defp count_cells(line) do
    line |> parse_row_cells(:bordered) |> length()
  end

  defp empty_key_row?(line, prev_line, mode, key_col_idx) do
    if table_line?(line) and not delimiter_line?(line) and not delimiter_line?(prev_line) do
      cells = parse_row_cells(line, mode)
      key_val = Enum.at(cells, key_col_idx, "")
      key_val == "" and cells != []
    else
      false
    end
  end

  defp merge_cell_by_cell(prev_line, curr_line, mode) when is_binary(curr_line) do
    curr_cells = parse_row_cells(curr_line, mode)
    merge_cell_by_cell(prev_line, curr_cells, mode)
  end

  defp merge_cell_by_cell(prev_line, curr_cells, _mode) when is_list(curr_cells) do
    prev_cells = parse_row_cells(prev_line, :bordered)
    max_len = max(length(prev_cells), length(curr_cells))

    merged_cells =
      0..(max_len - 1)
      |> Enum.map(fn i ->
        p = Enum.at(prev_cells, i, "")
        c = Enum.at(curr_cells, i, "")
        clean_p = String.replace(String.trim(p), ~r/\\$/, "")
        c_converted = convert_inline_double_backslashes(String.trim(c))

        cond do
          clean_p != "" and c_converted != "" ->
            clean_p <> "<br>" <> c_converted

          clean_p != "" ->
            clean_p

          c_converted != "" ->
            c_converted

          true ->
            ""
        end
      end)

    format_row_cells(merged_cells)
  end

  defp convert_inline_double_backslashes(line) do
    if delimiter_line?(line) do
      line
    else
      String.replace(line, ~r/(?<!\\)\\\\(?!\|)/, "<br>")
    end
  end

  defp delimiter_line?(line) do
    trimmed = String.trim(line)
    String.match?(trimmed, ~r/^\|?[\s:\-]+\|[\s:\-|]*$/)
  end

  defp code_fence_start(line) do
    cond do
      String.starts_with?(line, "```") -> "```"
      String.starts_with?(line, "~~~") -> "~~~"
      true -> nil
    end
  end

  defp table_line?(line) do
    trimmed = String.trim(line)
    String.contains?(line, "|") and not String.starts_with?(trimmed, "```")
  end

  defp count_pipes(line) do
    line
    |> String.replace("\\|", "")
    |> String.graphemes()
    |> Enum.count(&(&1 == "|"))
  end

  defp has_trailing_backslash?(line) do
    String.match?(line, ~r/\\\s*\|?\s*$/)
  end

  defp unclosed_row?(line, mode, expected_cols) do
    cells = parse_row_cells(line, mode)
    cells != [] and length(cells) < expected_cols
  end
end
