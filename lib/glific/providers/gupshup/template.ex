defmodule Glific.Providers.Gupshup.Template do
  @moduledoc """
  Message API layer between application and Gupshup
  """

  alias Glific.{
    Partners,
    Partners.Organization,
    Providers.Gupshup.ApiClient,
    Templates,
    Templates.SessionTemplate
  }

  @doc """
  Submitting HSM template for approval
  """
  @spec submit_for_approval(map()) :: {:ok, SessionTemplate.t()} | {:error, String.t()}
  def submit_for_approval(attrs) do
    organization = Partners.organization(attrs.organization_id)

    with {:ok, response} <-
           ApiClient.submit_template_for_approval(
             attrs.organization_id,
             body(attrs, organization)
           ),
         {200, _response} <- {response.status, response} do
      {:ok, response_data} = Jason.decode(response.body)

      attrs
      |> Map.merge(%{
        number_parameters: length(Regex.split(~r/{{.}}/, attrs.body)) - 1,
        uuid: response_data["template"]["id"],
        status: response_data["template"]["status"],
        is_active:
          if(response_data["template"]["status"] == "APPROVED",
            do: true,
            else: false
          )
      })
      |> Templates.do_create_session_template()
    else
      {status, response} ->
        # structure of response body can be different for different errors
        {:error, ["BSP response status: #{to_string(status)}", handle_error_response(response)]}

      _ ->
        {:error, ["BSP", "couldn't submit for approval"]}
    end
  end

  @spec handle_error_response(map() | String.t()) :: String.t()
  defp handle_error_response(response) when is_binary(response), do: response

  defp handle_error_response(response) do
    Jason.decode(response.body)
    |> case do
      {:ok, data} ->
        if Map.has_key?(data, "message"), do: data["message"], else: "Something went wrong"

      _ ->
        "Error in decoding response body"
    end
  end

  @doc """
  Updating HSM templates for an organization
  """
  @spec update_hsm_templates(non_neg_integer()) :: :ok | {:error, String.t()}
  def update_hsm_templates(organization_id) do
    organization = Partners.organization(organization_id)

    with {:ok, response} <-
           ApiClient.get_templates(organization_id),
         {:ok, response_data} <- Jason.decode(response.body),
         false <- is_nil(response_data["templates"]) do
      Templates.do_update_hsms(response_data["templates"], organization)
      :ok
    else
      _ ->
        {:error, ["BSP", "couldn't connect"]}
    end
  end

  @spec body(map(), Organization.t()) :: map()
  defp body(attrs, organization) do
    language =
      Enum.find(organization.languages, fn language ->
        to_string(language.id) == to_string(attrs.language_id)
      end)

    %{
      elementName: attrs.shortcode,
      languageCode: language.locale,
      content: attrs.body,
      category: attrs.category,
      vertical: attrs.label,
      templateType: String.upcase(Atom.to_string(attrs.type)),
      example: attrs.example
    }
    |> update_as_button_template(attrs)
  end

  defp update_as_button_template(template_payload, %{has_buttons: true} = attrs) do
    template_payload |> Map.merge(%{buttons: add_buttons(attrs.button_type, attrs.buttons)})
  end

  defp update_as_button_template(template_payload, _attrs) do
    template_payload
  end

  defp add_buttons("QUICK_REPLY", buttons) do
    buttons
  end

  defp add_buttons("Call_to_action", buttons) do
    buttons
  end
end
