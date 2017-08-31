defmodule JiraUser do
  defstruct server: "", 
    user: "",
    pass: "",
    display_name: "",
    email_address: "",
    avatar: ""

  def all(), do: all(config_user())
  def all(%JiraUser{} = user) do
    wildcard = user_wildcard(user)
    batch_size = 1000
    fetch(user, 0, batch_size, wildcard, [])
  end

  @doc """
  Returns the user wildcard to use depending on the jira version server
  """
  defp user_wildcard(%JiraUser{} = user) do
    version = server_version(user)
    cond do
      Version.match? version, ">7.4.0" -> "%"
      true -> "."
    end
  end

  defp server_version(%JiraUser{} = user) do
    url = "#{user.server}/rest/api/2/serverInfo"
    case HTTPoison.get url, headers(user) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        body 
        |> Poison.decode!
        |> Map.get("version")
        |> Version.parse!
    end
  end

  defp fetch(user, from, size, wildcard, results) do
    url = batch_query(user, from, size, wildcard)
    case HTTPoison.get url, headers(user) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        users = parse_response body
        results = results ++ users
        cond do
          length(users) == size -> 
            fetch(user, from + size, size, wildcard, results)
          true -> 
            results
            |> Enum.sort_by(&(&1.display_name))
        end
    end     
  end

  defp parse_response(response) do
    response
    |> Poison.decode!
    |> Enum.map(&%JiraUser{
      display_name: &1["displayName"],
      user: &1["name"],
      email_address: &1["emailAddress"]
    })
  end

  defp batch_query(%JiraUser{server: server}, from, size, userfilter) do
    "#{server}/rest/api/2/user/search?username=#{userfilter}&startAt=#{from}&maxResults=#{size}"
  end

  def headers(%JiraUser{user: user, pass: pass}) do
    headers(user, pass)
  end
  def headers(user, pass) do
    token = Base.encode64("#{user}:#{pass}")
    ["Authorization": "Basic #{token}"]
  end

  def config_user do
    domain = Application.get_env(:jira_log, :server)
    user = Application.get_env(:jira_log, :user)
    pass = Application.get_env(:jira_log, :pass)
    %JiraUser{server: domain, user: user, pass: pass}
  end

end
