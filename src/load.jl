# Read ini-style lecture description
using IniFile

const MAX_GROUP_SIZE = 16

const MAXIMUM_FILE = "Maximal.csv"
const SCORES_FILE = "punkte.csv"
const SCORES_STACKED = "punkte_stacked.csv"
const NAMES_FILE = "Namen.csv"
const EXAM = "klausur"

"""
Read the lecture description which includes the name, a short name and the term
in which the lecture takes place.

#### Arguments

* `dir::AbstractString`: The directory of the lecture.

#### Returns

* `data::LectureData`: The LectureData struct populated with the information
from the ini file.
"""
function read_lecture_desc(dir::AbstractString)
    new_scores = Scores(-1, -1, -1, DataFrame(), -1, DataFrame(), DataFrame(), Union{})

    path = joinpath(dir, "lecture.ini")
    if !isfile(path)
        info("Could not find file 'lecture.ini', using default values")
        return LectureData("", "", "", DataFrame(), new_scores, [])
    end
    ini_file = read(Inifile(), path)

    name = get(ini_file, "name")
    short_name = get(ini_file, "short_name")
    term = get(ini_file, "term")

    scores_path = joinpath(dir, "punkte")

    # Student id, name (or given name & surname), course of study
    types = [Int, UTF8String, UTF8String, UTF8String]
    names = readtable(joinpath(scores_path, NAMES_FILE), eltypes=types)

    LectureData(name, short_name, term,
                dir, scores_path, joinpath(dir, "output"),
                names, new_scores, [])
end


"Read the individual score files and create the stacked file."
function stack_data!(data::LectureData)
    # TODO check whether the stacked file is up to date
    maximum_scores = data.exercises.maximum_scores
    files = map((x,y) -> string(x, ".", y, ".csv"), maximum_scores[:Blatt], maximum_scores[:Aufgabe])

    sheets = Int[]
    exercises = UTF8String[]
    scores = Float64[]
    students = Int[]
    for (sheet,exercise) in zip(maximum_scores[:Blatt], maximum_scores[:Aufgabe])
        file = joinpath(data.scores_directory, string(sheet, ".", exercise, ".csv"))
        try
            csv = readcsv(file)
            for i in 1:size(csv,1)
                line = csv[i,:]
                if line[1] == "Punkte"
                    continue
                end
                for id in line[2:end]
                    if id == ""
                        break
                    end
                    push!(sheets, sheet)
                    push!(exercises, exercise)
                    push!(scores, line[1])
                    push!(students, id)
                end
            end
        catch err
            info("Could not read scores for sheet $sheet, exercise $exercise.")
            warn(err)
            break
        end
    end
    if length(sheets) != 0
        info("Writing stacked data to disk")
        df = DataFrame(Blatt=sheets, Aufgabe=exercises, Matrikelnummer=students, Punkte=scores)

        stacked_file = joinpath(data.scores_directory, SCORES_STACKED)
        writetable(stacked_file, df)
    else
        info("Using existsing stacked data file.")
    end
end


"Load the maximum scores from disk."
function load_maximum!(data::LectureData)
    path = joinpath(data.scores_directory, MAXIMUM_FILE)
    if !isfile(path)
        info("Could not find file with the maximum possible scores")
        return Union{}
    end
    types = [Int, UTF8String, Int, Int] # Make sure the exercise name is read as a string
    ex = data.exercises
    ex.maximum_scores = readtable(path, eltypes=types)

    # FIXME This assumes that the columns in Maximal.csv are sheet, exercise,
    # followed by the maximum score.
    ex.perfect_score = sum(ex.maximum_scores[end])
    ex.number_of_assignments = nrow(ex.maximum_scores)

    return data
end


"Load raw scores."
function load_data!(data::LectureData)
    dir = data.scores_directory

    # Load the scores
    scores = readtable(joinpath(dir, SCORES_FILE))

    # Reshape the scores to map exercise numbers to scores.
    scores = melt(scores, :Matrikelnummer)
    scores = by(scores, [:Matrikelnummer, :variable, :value]) do df
        # Parse the symbols containing the exercise and sheet number.  The
        # data is of the form `:A1_2` where `1` is the number of the
        # assignment sheet and `2` is the number of the exercise.
        name = string(df[:variable][1])
        (sheet, exercise) = split(name[2:end], "_")
        DataFrame(Blatt=parse(Int, sheet), Aufgabe=exercise)
    end
    rename!(scores, :value, :Punkte)

    data.exercises.scores = scores[[:Blatt, :Aufgabe, :Matrikelnummer, :Punkte]]
    data.number_of_students = length(unique(scores[:Matrikelnummer]))

    return data
end


"""
Read exercise scores from `\$dir/punkte_stacked.csv`.  The table has a column
for the sheet and exercise numbers, the student id and the number of points
obtained by that student for the given sheet and exercise number.
"""
function load_stacked_data!(data::LectureData)
    path = joinpath(data.scores_directory, SCORES_STACKED)

    types = [Int, UTF8String, Int, Float64] # Sheet, exercise, student id, score
    scores = readtable(path, eltypes=types)

    ex = data.exercises
    ex.number_of_students = length(unique(scores[:Matrikelnummer]))
    ex.scores = scores[[:Blatt, :Aufgabe, :Matrikelnummer, :Punkte]]

    return data
end


"Read all the data from exams 1 and 2 (if it is available)"
function load_exam_data!(data::LectureData)
    dir = data.scores_directory

    for i in [1,2]
        # TODO try to load the stacked variant first
        scores_file = joinpath(dir, EXAM * string(i) * ".csv")
        maximum_file = joinpath(dir, EXAM * string(i) * "_maximal.csv")
        if isfile(maximum_file)
            info("Reading data for exam $i")
            # Types: Given name, surname, course of studies, student id, scores
            # per assignment, total score, grade
            types = [UTF8String, UTF8String, UTF8String, Int]
            append!(types, collect(repeated(Float64, 32))) # HACK
            scores = readtable(scores_file, eltypes=types)

            # TODO automatically insert students' names and ids and into the
            # data.names data frame

            # Assuming that the columns are name, student id, scores for
            # assignments, total score and grade, compute the stacked scores.
            totals = scores[[:Matrikelnummer, :Σ, :Note]]

            # Skip columns with the students' given and surnames, as well as their study paths.
            scores = melt(scores[4:end-2], :Matrikelnummer)

            number_of_students = nrow(totals)

            maximum_scores = readtable(maximum_file)
            number_of_assignments = nrow(maximum_scores)
            perfect_score = sum(maximum_scores[end]) # HACK this only works for one set of scores

            bonus_points = 0
            if haskey(maximum_scores, :Bonus)
                bonus_points = sum(maximum_scores[:Bonus])
            end

            grade_minimums_file = joinpath(data.scores_directory, EXAM * string(i) * "_noten.csv")
            grade_minimums = if isfile(grade_minimums_file)
                readtable(grade_minimums_file)
            else
                Union{}
            end

            foo = Scores(number_of_assignments, perfect_score, bonus_points,
                         maximum_scores, number_of_students, scores, totals,
                         grade_minimums)

            push!(data.exams, foo)
        end
    end

    data
end
