defmodule JiraUser do
  defstruct server: "", 
    user: "",
    pass: "",
    display_name: "",
    email_address: "",
    avatar: ""

  def all(), do: all(config_user())
  def all(%JiraUser{} = user) do
    batch_size = 1000
    fetch(user, 0, batch_size, [])
  end

  defp fetch(user, from, size, results) do
    url = batch_query(user, from, size)
    case HTTPoison.get url, headers(user) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        users = parse_response body
        results = results ++ users
        cond do
          length(users) == size -> 
            fetch(user, from + size, size, results)
          true -> 
            results
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

  defp batch_query(%JiraUser{server: server}, from, size) do
    "#{server}/rest/api/2/user/search?username=.&startAt=#{from}&maxResults=#{size}"
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
