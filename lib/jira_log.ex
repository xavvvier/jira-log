defmodule JiraLog do
  require IEx

  defp user do
    domain = Application.get_env(:jira_log, :server)
    user = Application.get_env(:jira_log, :user)
    pass = Application.get_env(:jira_log, :pass)
    %JiraUser{server: domain, user: user, pass: pass}
  end

  defp today_user_filter do
    user = Application.get_env(:jira_log, :user)
    {erl_date, _} = :calendar.local_time()
    {:ok, date} = Date.from_erl(erl_date)
    iso_date = Date.to_iso8601(date)
    %WorklogFilter{user: user, date: iso_date}
  end

  defp headers(user, pass) do
    token = Base.encode64("#{user}:#{pass}")
    ["Authorization": "Basic #{token}"]
  end

  @doc """
  Retrieves the issues modified on the current date for the current user
  The issues are returned as a list of tuples (issue_id, description)
  """
  def query(%JiraUser{server: server, user: user, pass: pass}, date) do
    #query = "assignee = currentUser()"
    query = "worklogAuthor = currentUser() AND worklogDate = #{date}"
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
  def list_logs, do: list_logs(today_user_filter(), user())
  def list_logs(%WorklogFilter{} = filter, %JiraUser{} = user) do
    query(user, filter.date)
    |> Enum.map(&(worklogs_for_issue(user, &1, filter)))
  end

  @doc """
  Print the total amount of worklog for the current user
  """
  def times do
    list  = list_logs()
    list
    |> Stream.flat_map(&(&1.times)) 
    |> Stream.map(&(&1.seconds)) 
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

  defp worklogs_for_issue(%JiraUser{server: server, user: user, pass: pass},
                          {issue_id, description},
    %WorklogFilter{} = filter
  ) do
    url = "#{server}/rest/api/2/issue/#{issue_id}/worklog"
    %HTTPoison.Response{status_code: 200, body: body} = HTTPoison.get! url, headers(user, pass)
    times = 
      body
      |> Poison.decode!
      |> filter(filter)
      |> extract_worklog
    %{issue: issue_id, description: description, times: times}
  end

  defp filter(response, %WorklogFilter{}=filter) do
    response["worklogs"]
    |> filter_user(filter.user)
    |> filter_date(filter.date)
  end

  defp filter_user(worklogs, ""), do: worklogs
  defp filter_user(worklogs, user) do
    worklogs
    |> Stream.filter(fn item ->
      item["author"]["emailAddress"] == user or 
      item["author"]["key"] == user
    end)
  end

  defp filter_date(worklogs, ""), do: worklogs
  defp filter_date(worklogs, date) do
    worklogs
    |> Stream.filter(fn item -> 
      String.starts_with?(item["started"], date) 
    end)
  end

  defp extract_worklog(worklogs) do
    worklogs
    |> Enum.map(fn item -> 
      %JiraWorklog{
        user: item["author"]["emailAddress"],
        seconds: item["timeSpentSeconds"],
        created: item["created"],
        started: item["started"],
        time_spent: item["timeSpent"],
        comment: item["comment"]
      }
    end) 
  end

end
