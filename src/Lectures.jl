module Lectures

import Base: zero

export analyse, compute_totals, generate_report, main, get_total, get_scores, lectures_with_scores, process_lectures

# TODO Make plots with lots of (differently named) exercises nicer
# TODO Handle exercises with different maximal scores properly
# TODO Figure out how to handle bonus points

using Colors
using DataFrames
using Gadfly
using IniFile

using Debug

include("data.jl")
include("load.jl")
include("plot.jl")

@doc doc"""Get a list of all subdirectories of a given directory which contain
scores.""" ->
function lectures_with_scores(base_dir::AbstractString)
  filter(x -> isdir(joinpath(base_dir, x)) && isfile(joinpath(base_dir, x, "lecture.ini")), readdir(base_dir))
end

function process_lectures(base_dir::AbstractString)
  lectures = lectures_with_scores(base_dir)
  for lecture in lectures
    info("Processing ", lecture)
    main(lecture)
  end
end

process_lectures() = process_lectures(expanduser("~/work"))


# Data analysis

@doc doc"""Compute the total score for each student.""" ->
function compute_totals(scores::DataFrame)
    return by(scores, [:Matrikelnummer]) do df
        DataFrame(total=sum(dropna(df[:Punkte])),
                  handed_in=count(x -> x >= 0, df[:Punkte]))
    end
end


@doc doc"""Analyse the raw data contained in `$dir/punkte.csv`.""" ->
function analyse(dir::AbstractString)
    @assert dir != ""
    data = read_lecture_desc(dir)

    load_maximum!(data)
    stack_data!(data)
    load_stacked_data!(data)
    try
      load_exam_data!(data)
    catch err
      if isa(err, KeyError)
        println(err)
      else
        error("Reading exam data failed:\n", string(err))
      end
    end

    data.exercises.totals = compute_totals(data.exercises.scores)

    plot_overview(data)
    plot_totals(data)
    scatter_plot_totals(data) # Scatter plot of student ids and totals

    for i in 1:length(data.exams)
        plot_exercise_exam_correlation(data, i)
        #plot_correlations_by_assignment(data, i)
    end

    report_file = joinpath(data.output_directory, "Auswertung.md")
    report_html = joinpath(data.output_directory, "Auswertung.html")
    open(report_file, "w") do file
        write(file, generate_report(data))
    end
    cmd = `pandoc --template $(Pkg.dir("Lectures") * "/templates/report.html")
                  -V lang=de --from markdown --to html $report_file -o $report_html`
    run(cmd)

    return data
end

function reduce_mod(nums, modulus)
  nums - nums % modulus
end


@doc doc"""Generate a report of the data.""" ->
function generate_report(data::LectureData)
    scores = data.exercises.scores
    totals = data.exercises.totals
    num_exercises = data.exercises.number_of_assignments
    cor_id_total = cor(totals[:Matrikelnummer], totals[:total])

    number_of_students = data.exercises.number_of_students
    mean_handed_in = count(x -> x >= 0, scores[:Punkte])/number_of_students
    mean_handed_in = round(mean_handed_in, 1)

    exams = UTF8String["", ""]
    for i in 1:length(data.exams)
        exams[i] = """## Ergebnisse von Klausur $i
        ![Vergleich der Ergebnisse von Klausur und Übungen](exam_exercise_correlation_$i.png)\\ ![Vergleich von Klausurergebnis und Anzahl der abgegebenen Übungen](exam_num_exercises_$i.png)\\
        """
#        ![Vergleich von Klausurergebnis mit den einzelnen Übungsblättern](cor_subtotals_$i.png)
#        ![Vergleich von Klausurergebnis mit den einzelnen Übungsaufgaben](cor_scores_$i.png)"""
    end

    cor_id_total = round(cor_id_total, 2)

    cor_totals_exam = UTF8String["", ""]
    for i in 1:length(data.exams)
        foo = join(totals, data.exams[i].totals, on=:Matrikelnummer, kind=:right)
        bar = isna(foo[:total])
        foo[bar, :total] = 0
        corellation = cor(foo[:total], foo[:Σ])
        correlation = round(corellation, 2)
        cor_totals_exam[i] = """* Zwischen den erreichten Punkten in den Übungen und der $i. Klausur besteht eine Korrelation mit Korrelationskoeffizient $correlation.
        * Es gaben insgesamt $(sum(bar)) Studenten an der $i. Klausur teilgenommen, aber nie Übungen abgegeben.  Ihre Matrikelnummern sind $(join(map(string, reduce_mod(foo[bar, :Matrikelnummer], 1000)), ", "))."""
    end

    return """---
lecture-name: $(data.name)
term: $(data.term)
language: de-DE
...

# Auswertung der Übungsergebnisse zur Vorlesung $(data.name) ($(data.term))
## Histogramm der Übungspunkte
![Histogramm der Übungspunkte](totals.png)\\


## Übersicht über die einzelnen Aufgaben
![Überblick über die einzelnen Aufgaben](overview.png)\\


## Auswertung der Gesamtpunktzahl
![Vergleich von Matrikelnummern und der Übungspunktzahl](scatter_totals.png)\\ ![Vergleich der Anzahl abgegebener Aufgaben und der Übungspunktzahl](scatter_number.png)\\


$(exams[1])

$(exams[2])

## Sonstige Daten
* Von den $number_of_students Teilnehmern wurden durchschnittlich
  $mean_handed_in der insgesamt $num_exercises Aufgaben abgegeben.
* Der Korrelationskoeffizient von Matrikelnummern und erreichten
  Gesamtpunktzahlen ist $cor_id_total.
$(cor_totals_exam[1])
$(cor_totals_exam[2])
"""
end


function main(project::AbstractString)
  project_path = joinpath(ENV["HOME"], "work", project)
  output_path = joinpath(project_path, "output")
  if !isdir(output_path)
    mkdir(output_path, 0o755)
  end
  analyse(project_path)
end


function get_total(data::LectureData, student::Int)
    totals = data.exercises.totals
    totals[totals[:Matrikelnummer] .== student, :total]
end


function get_scores(data::LectureData, student::Int)
    scores = data.exercises.scores
    scores[scores[:Matrikelnummer] .== student, [:Blatt, :Aufgabe, :Punkte]]
end

end # module
