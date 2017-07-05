defmodule JiraLog do

  defp user do
    domain = Application.get_env(:jira_log, :server)
    user = Application.get_env(:jira_log, :user)
    pass = Application.get_env(:jira_log, :pass)
    %JiraUser{server: domain, user: user, pass: pass}
  end

  @doc """
  Retrieves the issues modified on the current date for the current user
  """
  def query, do: query(user)
  def query(%JiraUser{:server => server, user: user, pass: pass}) do
    #query = "assignee = currentUser()"
    query = "worklogAuthor = currentUser() AND worklogDate >= startOfDay()"
    fields = "key,summary"
    search_url = "#{server}/rest/api/2/search?jql=#{query}&fields=#{fields}&maxResults=10000"
    case HTTPoison.get! URI.encode(search_url), headers(user, pass) do 
      %HTTPoison.Response{status_code: 200, body: body} ->
      body
      |> Poison.decode!
      |> list_of_issues
    end
  end

  @doc """
  List all the worklog items on the current date for the current user
  """
  def list_logs, do: list_logs(user)
  def list_logs(%JiraUser{} = user) do
    query(user)
    |> Enum.map(&(time_for_issue(user, &1)))
  end

  @doc """
  Print the total amount of worklog for the current user
  """
  def times do
    list  = list_logs
    list
    |> Stream.flat_map(&(&1.times)) 
    |> Stream.filter(&(elem(&1, 0) == "egonzales@kcura.com")) 
    |> Stream.map(&(elem(&1, 1))) 
    |> Enum.reduce(0, &+/2)
    |> format_seconds
    |> IO.puts

    list
    |> Enum.each(&IO.inspect/1)
  end

  def format_seconds(seconds) do
    h = div(seconds, 3600)
    "#{h}h #{div(seconds - h * 3600, 60)}m"
  end

  defp list_of_issues(response) do
    response["issues"]
    |> Enum.map(fn item -> {item["key"], item["fields"]["summary"]} end)
  end

  defp time_for_issue(%JiraUser{server: server, user: user, pass: pass},
                      {id, _} = issue) do
    url = "#{server}/rest/api/2/issue/#{id}/worklog"
    %HTTPoison.Response{status_code: 200, body: body} = HTTPoison.get! url, headers(user, pass)
    times = 
      body
      |> Poison.decode!
      |> extract_time
    %{issue: issue, times: times}
  end

  defp headers(user, pass) do
    token = Base.encode64("#{user}:#{pass}")
    ["Authorization": "Basic #{token}"]
  end

  defp extract_time(response) do
    response["worklogs"]
    |> Enum.map(fn item -> {item["author"]["emailAddress"], item["timeSpentSeconds"]} end) 
  end

end
