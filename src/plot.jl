# Plot size
width = 1890px
height = 800px

set_default_plot_size(width, height)

# Colors gradients
totals_gradient = Scale.lab_gradient(map(x -> parse(Colorant, x),
                                         ["lightgrey", "red", "orange", "yellow", "green", "blue"])...)
marks_gradient(p) = totals_gradient(1-p)


"""
Create a function which maps a number from [0,1] to a color from the given
gradient.
"""
function color_chooser(gradient)
    return p -> gradient(if p < 1/3; 0.0; else 3*p/2-1/2; end)
end


"""
Save a plot to disk as a PNG file.

#### Arguments

* `dir::AbstractString`: The directory in which the generated image is stored.
* `filename::AbstractString`: The file name of the image.
* `width`: How wide the plot is supposed to be (in cm, pixels, etc.).
* `height`: How high the plot is supposed to be (in cm, pixels, etc.).
* `plot`: The plot to be stored.

#### Examples

    save_plot("/tmp", "image", 800px, 600px, Gadfly.plot(...))

"""
function save_plot(dir::AbstractString, filename::AbstractString, width, height, plot)
    draw(PNG(joinpath(dir, filename * ".png"), width, height), plot)
end


"""
Compute totals for all the students and plot a histogram.
"""
function plot_totals(data::LectureData)
    info("Plotting totals...")
    perfect_score = data.exercises.perfect_score
    totals = data.exercises.totals

    #count_totals = by(totals, :total, df -> DataFrame(count = nrow(df)))
    bins = data.exercises.number_of_assignments

    p = plot(totals, x=:total, color=:Matrikelnummer,
             xintercept=perfect_score/100*[30, 40, 50],
             Geom.vline(color=colorant"red") ,
             Geom.histogram(bincount=bins),
             Guide.colorkey("Matnr."),
             Guide.xlabel("Gesamtpunktzahl"),
             Guide.ylabel("Häufigkeit", orientation=:vertical),
             Guide.xticks(ticks=[0:8:maximum(totals[:total])]),
             Scale.ContinuousColorScale(totals_gradient),
             Theme(background_color=colorant"white"))

    save_plot(data.output_directory, "totals", width, 200px, p)
end

function relative_score(scores, maxs)
    result = copy(scores)
    result[maxs .!= 0] ./= maxs[maxs .!= 0]
    result[maxs .== 0] ./= abs(result[maxs .== 0])
    result[result .< 0] = -0.75
    result
end


"""
Figure out and plot how often every possible score occurred for each of the
assignments.
"""
function plot_overview(data::LectureData)
    info("Plotting overview")
    scores = data.exercises.scores
    num_students = data.exercises.number_of_students
    maximum_scores = data.exercises.maximum_scores

    # Count how often specific scores occur for a given exercise.
    counted_scores = by(scores, [:Blatt, :Aufgabe, :Punkte]) do df
      DataFrame(count=nrow(df))
    end

    na_score = -1.0*maximum(maximum_scores[end])

    # Set NA to -1 to indicate exercises not handed in.
    if sum(counted_scores[:Punkte].na) > 0
        counted_scores[:Punkte][counted_scores[:Punkte].na] = na_score
    else
        count_hand_ins = by(counted_scores, [:Blatt, :Aufgabe]) do df
            DataFrame(Punkte=na_score, count=num_students-sum(df[:count]))
        end
        append!(counted_scores, count_hand_ins)
    end

    # TODO handle lecture with just one maximum score for every exercise
    foo = if :Fach in names(maximum_scores)
        rename(maximum_scores, :Fach, :Maximum)
    elseif :Punkte in names(maximum_scores)
        rename(maximum_scores, :Punkte, :Maximum)
    else
        error("Could not read maximum scores")
    end
    with_max = join(counted_scores, foo, on = [:Blatt, :Aufgabe])
    weighted = by(with_max, [:Blatt, :Aufgabe, :count, :Punkte]) do df
        DataFrame(weighted=relative_score(df[:Punkte], df[:Maximum]))
    end
    sort!(weighted, cols=[:Blatt, :Aufgabe, :Punkte])

    # Create a stacked bar chart.
    p = plot(weighted, xgroup=:Blatt, x=:Aufgabe, y=:count, color=:weighted,
             Geom.subplot_grid(free_x_axis=true,
                               Geom.bar(position=:stack),
                               Guide.yticks(ticks=collect(0:10:num_students))),
             Guide.xlabel("Blatt/Aufgabe"),
             Guide.ylabel("Abgaben"),
             Guide.colorkey("Punkte"),
             Scale.y_continuous(minvalue=0, maxvalue=num_students),
             Scale.ContinuousColorScale(color_chooser(totals_gradient)),
             Theme(background_color=colorant"white"))

    save_plot(data.output_directory, "overview", width, height, p)
end


#"""
#Plot the total scores obtained in the exercises against the student id and the
#number of exercises handed in, respectively.
#"""
@debug function scatter_plot_totals(data::LectureData)
    info("Creating scatter plots for exercises")
    totals = data.exercises.totals
    perfect_score = data.exercises.perfect_score
    number_of_assignments = data.exercises.number_of_assignments
    p = plot(totals, x=:Matrikelnummer, y=:total, color=:handed_in,
             Geom.point,
             Guide.xlabel("Matrikelnummer"),
             Guide.ylabel("Gesamtpunktzahl"),
             Guide.colorkey("Abgaben"),
             Guide.yticks(ticks=map(round, linspace(0, perfect_score, 10))),
             Scale.ContinuousColorScale(totals_gradient,
                                        minvalue = 0,
                                        maxvalue = 4+number_of_assignments)
             )

    save_plot(data.output_directory, "scatter_totals", 800px, 600px, p)

    p = plot(totals, x=:handed_in, y=totals[:total]./totals[:handed_in],
             color=:Matrikelnummer, Geom.point,
             Guide.xlabel("Anzahl abgegebener Übungsufgaben"),
             Guide.ylabel("Durchschnittliche Punktzahl"),
             Guide.colorkey("Matnr."),
             Scale.ContinuousColorScale(totals_gradient))

    save_plot(data.output_directory, "scatter_number", 800px, 600px, p)
end


function make_ticks(from, to, num_steps=8)
    map(round, linspace(from, to, num_steps))
end

function zero(x::AbstractString)
    ""
end


"""
Create scatter plots comparing the totals score in a given exam with the
exercise scores/number of exercises handed in.
"""
function plot_exercise_exam_correlation(data::LectureData, i::Int)
    info("Creating scatter plots for exams")
    perfect_score = data.exercises.perfect_score
    exam_perfect_score = data.exams[i].perfect_score
    totals = data.exercises.totals

    foo = join(totals, data.exams[i].totals, on=:Matrikelnummer, kind=:right)
    foo = join(foo, data.students, on=:Matrikelnummer, kind=:left)

    for col in 1:ncol(foo)
        foo[isna(foo[col]), col] = zero(foo[col].data[1])
    end

    grade_mins = data.exams[i].grade_minimums
    xintercept = if grade_mins != Union{}
        grade_mins = grade_mins[grade_mins[:Note] .== round(grade_mins[:Note]), :]
        grade_mins[:Punkte] - 0.25
    else
        exam_perfect_score/100 * [50]
    end
    foo[:Σ] *= 100/exam_perfect_score
    foo[:total] *= 100/perfect_score

    marks_scale = Scale.ContinuousColorScale(marks_gradient)

    p = plot(foo, x=:Σ, y=:total, color=:Note, Geom.point,
             #label=:Name, Geom.label,
             Guide.xlabel("Punkte in der Klausur"),
             Guide.ylabel("Punkte in den Übungen"),
             Guide.colorkey("Note"),
             Guide.xticks(ticks=collect(0:10:100)),
             Guide.yticks(ticks=collect(0:10:100)),
             marks_scale)

    outdir = data.output_directory
    save_plot(outdir, "exam_exercise_correlation_" * string(i), 800px, 600px, p)

    number_of_assignments = data.exercises.number_of_assignments
    p = plot(foo, x=:Σ, y=:handed_in, color=:Note, Geom.point,
             Guide.xlabel("Punkte in der Klausur"),
             Guide.ylabel("Abgegebene Übungsaufgaben"),
             Guide.colorkey("Note"),
             Guide.xticks(ticks=collect(0:10:100)),
             Guide.yticks(ticks=make_ticks(0, number_of_assignments, 8)),
             marks_scale)

    save_plot(outdir, "exam_num_exercises_" * string(i), 800px, 600px, p)
end


"""
Generate grids of scatter plots of exam scores compared to individual exercise
scores or per-sheet totals of the exercises.
"""
function plot_correlations_by_assignment(data::LectureData, i::Int)
    info("Plot correlation between exam and exercise scores per sheet")
    scores = data.exercises.scores
    totals = data.exams[i].totals
    foo = join(data.exercises.scores, totals, on=:Matrikelnummer, kind=:right)

    for row in 1:nrow(foo)
        if !isna(foo[row, :Blatt])
            continue
        end
        df = deepcopy(data.exercises.maximum_scores)
        df[:Aufgabe] = map(string, df[:Aufgabe])
        for col in [:Matrikelnummer, :Σ, :Note]
            df[col] = foo[row, col]
        end
        df[:Punkte] = 0
        foo = vcat(foo, df)
    end
    complete_cases!(foo)

    subtotals = by(foo, [:Matrikelnummer, :Blatt]) do df
        DataFrame(Aufgabe=df[:Aufgabe], Punkte=df[:Punkte], Note=df[:Note],
                  Σ=df[:Σ], subtotal = sum(df[:Punkte]))
    end

    foo = by(subtotals, [:Blatt]) do df
        DataFrame(Matrikelnummer=df[:Matrikelnummer], subtotal=df[:subtotal],
                  Σ=df[:Σ], Note=df[:Note], cor = cor(df[:Punkte], df[:Σ]))
    end

    p = plot(foo, x=:subtotal, y=:Σ, color=:cor, xgroup=:Blatt,
             Geom.subplot_grid(Geom.point),
             Guide.xlabel("Übungspunkte je Blatt"),
             Guide.ylabel("Klausurpunkte"),
             Guide.colorkey("Kor."),
             Scale.ContinuousColorScale(totals_gradient),
             Theme(background_color = colorant"white"))

    outdir = data.output_directory
    save_plot(outdir, "cor_subtotals_" * string(i), width, 350px, p)

    bar = by(subtotals, [:Blatt, :Aufgabe]) do df
        DataFrame(Punkte = df[:Punkte], Σ=df[:Σ], Note=df[:Note],
                  cor=cor(df[:Punkte], df[:Σ]))
    end
    bar[isnan(bar[:cor]), :cor] = 0

    p = plot(bar, x=:Punkte, y=:Σ, color=:cor, xgroup=:Blatt, ygroup=:Aufgabe,
             Geom.subplot_grid(Geom.point),
             Guide.xlabel("Übungspunkte je Aufgabe"),
             Guide.ylabel("Klausurpunkte bzw. Übungsblatt"),
             Guide.colorkey("Kor."),
             Scale.ContinuousColorScale(totals_gradient),
             Theme(background_color = colorant"white"))

    save_plot(outdir, "cor_scores_" * string(i), width, 1100px, p)
end
