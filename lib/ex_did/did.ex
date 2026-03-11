defmodule ExDid.DID do
  @moduledoc """
  Parsed bare DID.
  """

  @enforce_keys [:value, :method, :method_specific_id]
  defstruct value: nil, method: nil, method_specific_id: nil

  @typedoc "Typed DID."
  @type t :: %__MODULE__{
          value: String.t(),
          method: String.t(),
          method_specific_id: String.t()
        }
end
