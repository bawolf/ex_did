defmodule ExDid.KeyMulticodec do
  @moduledoc false

  import Bitwise

  alias ExDid.Base58Btc

  @typedoc false
  @type key_type :: :ed25519 | :x25519 | :secp256k1 | :p256 | :p384 | :p521 | :rsa

  @curve25519_prime (1 <<< 255) - 19

  @codecs %{
    <<0xED, 0x01>> => {:ed25519, "Multikey"},
    <<0xEC, 0x01>> => {:x25519, "Multikey"},
    <<0xE7, 0x01>> => {:secp256k1, "Multikey"},
    <<0x80, 0x24>> => {:p256, "Multikey"},
    <<0x81, 0x24>> => {:p384, "Multikey"},
    <<0x82, 0x24>> => {:p521, "Multikey"},
    <<0x85, 0x24>> => {:rsa, "Multikey"}
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

  @spec public_jwk(String.t()) :: {:ok, map()} | {:error, atom()}
  def public_jwk(multibase) when is_binary(multibase) do
    with {:ok, bytes} <- Base58Btc.decode(multibase),
         {:ok, descriptor} <- decode(bytes) do
      to_public_jwk(descriptor)
    end
  end

  @spec to_public_jwk(%{key_type: key_type(), public_key_bytes: binary()}) ::
          {:ok, map()} | {:error, atom()}
  def to_public_jwk(%{key_type: :ed25519, public_key_bytes: <<x::binary-size(32)>>}) do
    {:ok,
     %{
       "kty" => "OKP",
       "crv" => "Ed25519",
       "x" => Base.url_encode64(x, padding: false)
     }}
  end

  def to_public_jwk(%{key_type: :x25519, public_key_bytes: <<x::binary-size(32)>>}) do
    {:ok,
     %{
       "kty" => "OKP",
       "crv" => "X25519",
       "x" => Base.url_encode64(x, padding: false)
     }}
  end

  def to_public_jwk(%{
        key_type: :secp256k1,
        public_key_bytes: <<4, x::binary-size(32), y::binary-size(32)>>
      }) do
    {:ok,
     %{
       "kty" => "EC",
       "crv" => "secp256k1",
       "x" => Base.url_encode64(x, padding: false),
       "y" => Base.url_encode64(y, padding: false)
     }}
  end

  def to_public_jwk(%{
        key_type: :p256,
        public_key_bytes: <<4, x::binary-size(32), y::binary-size(32)>>
      }) do
    {:ok,
     %{
       "kty" => "EC",
       "crv" => "P-256",
       "x" => Base.url_encode64(x, padding: false),
       "y" => Base.url_encode64(y, padding: false)
     }}
  end

  def to_public_jwk(%{
        key_type: :p384,
        public_key_bytes: <<4, x::binary-size(48), y::binary-size(48)>>
      }) do
    {:ok,
     %{
       "kty" => "EC",
       "crv" => "P-384",
       "x" => Base.url_encode64(x, padding: false),
       "y" => Base.url_encode64(y, padding: false)
     }}
  end

  def to_public_jwk(%{
        key_type: :p521,
        public_key_bytes: <<4, x::binary-size(66), y::binary-size(66)>>
      }) do
    {:ok,
     %{
       "kty" => "EC",
       "crv" => "P-521",
       "x" => Base.url_encode64(x, padding: false),
       "y" => Base.url_encode64(y, padding: false)
     }}
  end

  def to_public_jwk(%{key_type: :rsa, public_key_bytes: bytes}) do
    with {:ok, {modulus, exponent}} <- der_decode_rsa_public_key(bytes) do
      {:ok,
       %{
         "kty" => "RSA",
         "n" => Base.url_encode64(modulus, padding: false),
         "e" => Base.url_encode64(exponent, padding: false)
       }}
    end
  end

  def to_public_jwk(_descriptor), do: {:error, :unsupported_multicodec}

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

  defp der_decode_rsa_public_key(<<0x30, rest::binary>>) do
    with {:ok, sequence, <<>>} <- der_take_value(rest),
         {:ok, modulus, remainder} <- der_take_integer(sequence),
         {:ok, exponent, <<>>} <- der_take_integer(remainder) do
      {:ok, {trim_der_integer(modulus), trim_der_integer(exponent)}}
    else
      _ -> {:error, :unsupported_multicodec}
    end
  end

  defp der_decode_rsa_public_key(_), do: {:error, :unsupported_multicodec}

  defp der_take_integer(<<0x02, rest::binary>>) do
    with {:ok, value, remainder} <- der_take_value(rest) do
      {:ok, value, remainder}
    end
  end

  defp der_take_integer(_), do: {:error, :unsupported_multicodec}

  defp der_take_value(<<length, rest::binary>>) when length < 0x80 do
    take_bytes(rest, length)
  end

  defp der_take_value(<<length_of_length, rest::binary>>) when length_of_length > 0x80 do
    octet_count = length_of_length - 0x80

    with true <- byte_size(rest) >= octet_count,
         <<length_bytes::binary-size(octet_count), body::binary>> <- rest,
         length = :binary.decode_unsigned(length_bytes),
         {:ok, value, remainder} <- take_bytes(body, length) do
      {:ok, value, remainder}
    else
      _ -> {:error, :unsupported_multicodec}
    end
  end

  defp der_take_value(_), do: {:error, :unsupported_multicodec}

  defp take_bytes(binary, count) when byte_size(binary) >= count do
    <<value::binary-size(count), remainder::binary>> = binary
    {:ok, value, remainder}
  end

  defp take_bytes(_binary, _count), do: {:error, :unsupported_multicodec}

  defp trim_der_integer(<<0, rest::binary>>), do: trim_der_integer(rest)
  defp trim_der_integer(<<>>), do: <<0>>
  defp trim_der_integer(bytes), do: bytes

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
