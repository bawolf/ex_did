defmodule ExDid.Base58Btc do
  @moduledoc false

  @alphabet ~c"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
  @indexes @alphabet |> Enum.with_index() |> Map.new()

  @spec encode(binary()) :: String.t()
  def encode(binary) when is_binary(binary) do
    encoded =
      binary
      |> :binary.decode_unsigned()
      |> do_encode([])
      |> case do
        [] -> "1"
        chars -> List.to_string(chars)
      end

    "z" <> prepend_leading_zeroes(binary, encoded)
  end

  @spec decode(String.t()) :: {:ok, binary()} | {:error, atom()}
  def decode("z" <> encoded), do: decode_base58(encoded)
  def decode(_), do: {:error, :invalid_multibase}

  defp decode_base58(encoded) do
    with {:ok, value} <- to_integer(String.to_charlist(encoded), 0) do
      {:ok, prepend_zeroes(encoded, :binary.encode_unsigned(value))}
    end
  end

  defp to_integer([], acc), do: {:ok, acc}

  defp to_integer([char | rest], acc) do
    case Map.fetch(@indexes, char) do
      {:ok, index} -> to_integer(rest, acc * 58 + index)
      :error -> {:error, :invalid_base58}
    end
  end

  defp do_encode(0, []), do: []
  defp do_encode(0, acc), do: acc

  defp do_encode(value, acc) do
    quotient = div(value, 58)
    remainder = rem(value, 58)
    do_encode(quotient, [Enum.at(@alphabet, remainder) | acc])
  end

  defp prepend_zeroes(encoded, binary) do
    zero_count =
      encoded
      |> String.graphemes()
      |> Enum.take_while(&(&1 == "1"))
      |> length()

    :binary.copy(<<0>>, zero_count) <> binary
  end

  defp prepend_leading_zeroes(binary, encoded) do
    prefix =
      binary
      |> :binary.bin_to_list()
      |> Enum.take_while(&(&1 == 0))
      |> Enum.map(fn _ -> "1" end)
      |> Enum.join()

    prefix <> encoded
  end
end
