type Scores
    number_of_assignments :: Int # == nrow(maximum_scores)

    perfect_score :: Int # 100%
    bonus_points :: Int # Best score theoretically attainable (includes all extra credit assignments)

    maximum_scores :: DataFrame

    number_of_students :: Int

    scores :: DataFrame # Table of assignments, students' ids and their scores with one row per student and assignment

    # Results obtained during analysis
    totals :: DataFrame # Table of total points per student

    grade_minimums # How much points you have to have if you want to have a certain grade
end


type LectureData
    name :: String
    short_name :: String # Abbreviated name
    term :: String # the term in which the lecture takes place

    # Paths
    directory :: String
    scores_directory :: String
    output_directory :: String

    # Table containing students' names, ids and possibly their course of study
    students #:: DataFrame

    exercises :: Scores
    exams :: Vector{Scores}
end
