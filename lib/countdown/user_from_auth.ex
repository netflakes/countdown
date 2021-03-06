defmodule Countdown.UserFromAuth do
  @moduledoc """
  Retrieve the user information from an auth request
  """
  require Logger
  require Poison

  alias Ueberauth.Auth
  alias Countdown.{Utils.ConfigUtils, UserRepo}

  def find_or_create(%Auth{provider: :identity} = auth) do
    print_auth_details(auth, :identity_provider)

    case validate_pass(auth.credentials) do
      :ok ->
        user_info = basic_info(auth)
        register_user(user_info)
        {:ok, user_info}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def find_or_create(%Auth{} = auth) do
    print_auth_details(auth, :basic)
    user_info = basic_info(auth)
    register_user(user_info)
    {:ok, user_info}
  end

  defp register_user(user_info) do
    user_attrs = %{
      auth0_id: user_info.id,
      email: user_info.email
    }

    {:ok, model, message} = UserRepo.register_user(user_attrs)
    print_register_details(model, message)
  end

  def logout_redirect_url do
    params = %{"client_id" => auth_client_id(), "returnTo" => return_to_url()}
    encoded_params = URI.encode_query(params)
    "https://#{auth_domain()}/v2/logout?#{encoded_params}"
  end

  def force_logout do
    logout_response = HTTPoison.get!(logout_redirect_url())

    case logout_response.status_code do
      302 -> {:ok, "successfully logged out"}
      status -> {:error, status, "logout failed!"}
    end
  end

  # github does it this way
  defp avatar_from_auth(%{info: %{urls: %{avatar_url: image}}}), do: image

  # facebook does it this way
  defp avatar_from_auth(%{info: %{image: image}}), do: image

  # default case if nothing matches
  defp avatar_from_auth(auth) do
    Logger.warn(auth.provider <> " needs to find an avatar URL!")
    Logger.debug(Poison.encode!(auth))
    nil
  end

  defp basic_info(auth) do
    %{
      id: auth.uid,
      email: email_from_auth(auth),
      name: name_from_auth(auth),
      avatar: avatar_from_auth(auth)
    }
  end

  defp email_from_auth(auth) do
    if auth.info.email do
      auth.info.email
    else
      nil
    end
  end

  defp name_from_auth(auth) do
    if auth.info.name do
      auth.info.name
    else
      name =
        [auth.info.first_name, auth.info.last_name]
        |> Enum.filter(&(&1 != nil and &1 != ""))

      cond do
        length(name) == 0 -> auth.info.nickname
        true -> Enum.join(name, " ")
      end
    end
  end

  defp validate_pass(%{other: %{password: ""}}) do
    {:error, "Password required"}
  end

  defp validate_pass(%{other: %{password: pw, password_confirmation: pw}}) do
    :ok
  end

  defp validate_pass(%{other: %{password: _}}) do
    {:error, "Passwords do not match"}
  end

  defp validate_pass(_), do: {:error, "Password Required"}

  defp return_to_url, do: ConfigUtils.return_to_url()

  defp auth_domain, do: auth_configs()[:domain]
  defp auth_client_id, do: auth_configs()[:client_id]

  defp auth_configs, do: Application.get_env(:ueberauth, Ueberauth.Strategy.Auth0.OAuth)

  defp print_auth_details(auth, method) do
    Logger.info("\n User Auth (with #{method}): \n")
    Logger.info(inspect(auth))
    Logger.info("\n done \n")
  end

  defp print_register_details(model, message) do
    Logger.info("\n user info: #{message}\n")
    Logger.info("\n current user id: #{inspect(model.id)}")
    Logger.info("\n done \n")
  end
end
