defmodule ExDid.KeyMulticodec do
  @moduledoc false

  import Bitwise

  alias ExDid.Base58Btc

  @typedoc false
  @type key_type :: :ed25519 | :x25519 | :secp256k1 | :p256 | :p384 | :p521

  @curve25519_prime (1 <<< 255) - 19

  @codecs %{
    <<0xED, 0x01>> => {:ed25519, "Ed25519VerificationKey2020"},
    <<0xEC, 0x01>> => {:x25519, "X25519KeyAgreementKey2020"},
    <<0xE7, 0x01>> => {:secp256k1, "Multikey"},
    <<0x80, 0x24>> => {:p256, "Multikey"},
    <<0x81, 0x24>> => {:p384, "Multikey"},
    <<0x82, 0x24>> => {:p521, "Multikey"}
  }

  @spec decode(binary()) ::
          {:ok,
           %{key_type: key_type(), verification_type: String.t(), public_key_bytes: binary()}}
          | {:error, atom()}
  def decode(<<prefix::binary-size(2), public_key::binary>>) do
    case Map.fetch(@codecs, prefix) do
      {:ok, {key_type, verification_type}} ->
        {:ok,
         %{key_type: key_type, verification_type: verification_type, public_key_bytes: public_key}}

      :error ->
        {:error, :unsupported_multicodec}
    end
  end

  def decode(_), do: {:error, :unsupported_multicodec}

  @spec derive_x25519_multibase(binary()) :: {:ok, String.t()} | {:error, atom()}
  def derive_x25519_multibase(<<public_key::binary-size(32)>>) do
    y =
      public_key
      |> :binary.bin_to_list()
      |> List.update_at(31, &band(&1, 0x7F))
      |> :binary.list_to_bin()
      |> decode_little_endian()

    denominator = Integer.mod(1 - y, @curve25519_prime)

    if denominator == 0 do
      {:error, :invalid_ed25519_point}
    else
      u =
        Integer.mod(
          (1 + y) * mod_pow(denominator, @curve25519_prime - 2, @curve25519_prime),
          @curve25519_prime
        )

      x25519_public_key = encode_little_endian(u, 32)
      {:ok, Base58Btc.encode(<<0xEC, 0x01, x25519_public_key::binary>>)}
    end
  end

  def derive_x25519_multibase(_), do: {:error, :invalid_ed25519_point}

  defp decode_little_endian(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.with_index()
    |> Enum.reduce(0, fn {byte, index}, acc ->
      acc + Bitwise.bsl(byte, index * 8)
    end)
  end

  defp encode_little_endian(value, size) do
    value
    |> do_encode_little_endian([])
    |> Enum.reverse()
    |> Enum.take(size)
    |> then(fn bytes ->
      bytes ++ List.duplicate(0, size - length(bytes))
    end)
    |> :binary.list_to_bin()
  end

  defp do_encode_little_endian(0, []), do: [0]
  defp do_encode_little_endian(0, acc), do: acc

  defp do_encode_little_endian(value, acc) do
    do_encode_little_endian(Bitwise.bsr(value, 8), [band(value, 0xFF) | acc])
  end

  defp mod_pow(_base, 0, _modulus), do: 1

  defp mod_pow(base, exponent, modulus) do
    do_mod_pow(Integer.mod(base, modulus), exponent, modulus, 1)
  end

  defp do_mod_pow(_base, 0, _modulus, acc), do: acc

  defp do_mod_pow(base, exponent, modulus, acc) do
    acc =
      if band(exponent, 1) == 1 do
        Integer.mod(acc * base, modulus)
      else
        acc
      end

    do_mod_pow(Integer.mod(base * base, modulus), Bitwise.bsr(exponent, 1), modulus, acc)
  end
end
