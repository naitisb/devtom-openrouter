# Developmental ToM norms

Empirical age norms from the child development literature that anchor DevToM's
12-dimension instrument. These norms are the basis for mapping LLMs to
developmental age equivalents: each dimension's validated age band tells us *when*
typically developing children acquire that theory-of-mind ability, and the
analysis pipeline uses these norms to estimate where each model sits on the 2-11
year developmental scale.

## 1. Canonical 12-dimension norms (source of truth for the item bank)

These are the 12 `tom_dimension` values, their `validated_age_band`, and `literature_basis` exactly as
tagged in `data/12dimToM_mcq_dataset.jsonl` / `data/12dimToM_freeresponse_dataset.jsonl`, in
developmental-acquisition order (the order encoded in `DIMENSION_DEVELOPMENTAL_ORDER` in
`src/constructs.py`). This table is the single source of truth for the age mapping; the
milestone detail in §3-§4 is supporting reference behind it.

| # | Dimension (`tom_dimension`) | Age band | Construct grouping (§2) | Literature basis (as tagged on items) |
|---|---|---|---|---|
| 1 | Diverse Desires | 2–3 yr | desire/intention | Wellman & Liu (2004) ToM Scale — Diverse Desires task |
| 2 | Diverse Beliefs | 3–4 yr | belief reasoning | Wellman & Liu (2004) ToM Scale — Diverse Beliefs task |
| 3 | Knowledge Access / Ignorance | 3–4 yr | knowledge access | Wimmer, Hogrefe & Perner (1988) seeing-leads-to-knowing; Pratt & Bryant (1990) |
| 4 | Emotion Recognition | 3–4 yr | emotion recognition | basic emotion recognition (Ekman); complex/social emotion (Widen & Russell 2008) |
| 5 | First-Order False Belief | 4–5 yr | belief reasoning | Wimmer & Perner (1983) Sally–Anne; Perner, Leekam & Wimmer (1987) Smarties |
| 6 | Intention vs. Accident | 4–5 yr | desire/intention | Piaget (1932) intentionality in moral judgment; Nunner-Winkler & Sodian (1988) |
| 7 | Hidden Emotion (Appearance vs. Reality) | 4–6 yr | emotion recognition | Harris, Donnelly, Guz & Pitt-Watson (1986) display rules; Gross & Ballif (1991) |
| 8 | White Lies / Prosocial Deception | 5–7 yr | deception (see §2) | Talwar & Lee (2002); Talwar, Murphy & Lee (2007) prosocial lie-telling |
| 9 | Second-Order False Belief | 6–7 yr | belief reasoning | Perner & Wimmer (1985) Ice-Cream Van task |
| 10 | Sarcasm | 6–8 yr | pragmatic understanding | Winner & Leekam (1991); Filippova & Astington (2008) |
| 11 | Irony | 6–8 yr | pragmatic understanding | Hancock, Dunham & Purdy (2000); Colston (2000) |
| 12 | Faux Pas Detection | 9–11 yr | pragmatic understanding | Baron-Cohen, O'Riordan, Stone, Jones & Plaisted (1999) Faux Pas Recognition Test |

> **Ordering note.** Dimensions 1–5 draw on the canonical Wellman & Liu (2004) ToM-scale ordering (the
> single most-cited developmental ToM sequence). Dimensions 6–12 ("advanced ToM") do not have one
> settled canonical acquisition order in the literature; their sequencing here is a best-effort
> synthesis and the analysis treats it as *approximate*, not a strict ruler. Where two dimensions share
> a band (e.g. Sarcasm/Irony 6–8 yr), their relative rank is a convention, not a measured difference.

> **⚠ Citation status (verified 2026-07-14).** BibTeX for all 15 item-bank
> sources above (Wimmer/Hogrefe/Perner 1988; Pratt & Bryant 1990; Ekman 1992; Widen & Russell 2008;
> Perner/Leekam/Wimmer 1987; Piaget 1932; Nunner-Winkler & Sodian 1988; Harris et al. 1986; Gross &
> Ballif 1991; Talwar/Murphy/Lee 2007; Winner & Leekam 1991; Filippova & Astington 2008;
> Hancock/Dunham/Purdy 2000; Colston 2000; Baron-Cohen et al. 1999) has been **drafted in §5**, with
> volume/issue/pages verified via web search against publisher/PubMed/ERIC records. Two things still
> need your sign-off: (1) **Ekman** — the item metadata cites only "(Ekman)"; §5 uses Ekman (1992),
> *An argument for basic emotions*, but Ekman & Friesen (1971) is the alternative if the intent was
> cross-cultural facial-expression recognition. (2) **Band discrepancies vs. §3–§4** — Knowledge Access
> is tagged 3–4 yr here (Wimmer/Hogrefe/Perner 1988; Pratt & Bryant 1990) vs. ~4–4.5 yr via Wellman &
> Liu in §3, and Faux Pas is 9–11 yr via Baron-Cohen here vs. 7–8 yr via Osterhaus & Koerber in §4. The
> §1 table wins for the item bank; reconcile or annotate each difference when you verify against the
> primary sources.

## 2. Construct grouping (interpretive, not a data field)

The five (plus deception) developmental **constructs** are retained only as an *interpretive grouping*
over the 12 dimensions — they are **not** a field in the dataset (items carry `tom_dimension`, not a
`construct`). Grouping:

- **Belief reasoning** — Diverse Beliefs (3–4 yr) · First-Order False Belief (4–5 yr) · Second-Order
  False Belief (6–7 yr). *The old "recursive order 0–3+" axis is expressed by these three graded
  dimensions rather than a separate `order` field.*
- **Knowledge access** — Knowledge Access / Ignorance (3–4 yr).
- **Desire / intention inference** — Diverse Desires (2–3 yr) · Intention vs. Accident (4–5 yr).
- **Emotion recognition** — Emotion Recognition (3–4 yr) · Hidden Emotion / Appearance vs. Reality
  (4–6 yr).
- **Pragmatic understanding** — Sarcasm (6–8 yr) · Irony (6–8 yr) · Faux Pas Detection (9–11 yr).
- **Deception** — White Lies / Prosocial Deception (5–7 yr). *Surfaced as its own dimension (resolving
  the prior "is deception a construct?" open question); it maps most naturally under desire/intention
  as an interpretive parent if a five-group view is needed.*

### Prior open questions — resolved by the 12-dimension scheme
- **Knowledge access had no tier** → now a first-class dimension with a band (3–4 yr). ✅
- **Belief reasoning's two tier schemes (recursive order vs. milestone Tier 0/2/2+)** → collapsed to
  three explicit, band-ordered belief dimensions; no separate recursive-order axis in the data. ✅
- **Faux-pas construct ownership (emotion vs. pragmatic)** → its own dimension (Faux Pas Detection),
  grouped under pragmatic/advanced social cognition; no longer forced into one parent. ✅
- **Deception disposition** → its own dimension (White Lies / Prosocial Deception). ✅

## 3. Milestone summary — belief reasoning by recursive order (supporting reference)

Retained as deeper reference behind the three belief dimensions in §1; ages verified against primary
sources with quotes.

| Reasoning order | Typical child age band | Key citation(s) | Notes |
|---|---|---|---|
| Order-0 (reality/desire) | ~2.5–3 years (pre-representational "desire psychology") | Wimmer & Perner (1983); Wellman, Cross, & Watson (2001) | Wimmer & Perner: "Bretherton and Beeghly (in press) found that at the age of 2 1/2 years the majority of children spontaneously used a substantial vocabulary about perception, volition, major emotions, and knowledge" (p. 105). Wellman et al.: young children's "initial understanding of persons amounts to a desire psychology...based on an initial, simplified understanding of three internal states: states of emotion, states of perception, and, especially, states of desire," lacking "internal mental representations of the world (prototypically beliefs)" (p. 657). |
| Diverse desires | ~3 years (earliest-passed item on the ToM scale) | Wellman & Liu (2004) | Tests that "different people may have different desires" for the same object (e.g., predicting Mr. Jones picks a cookie he likes even though the child prefers a carrot). 4-year-olds (M = 4;0) pass this while failing every later scale item. |
| Diverse beliefs | ~3.5–4 years (passes shortly after diverse desires) | Wellman & Liu (2004) | Tests that "different people can have different beliefs" about an unseen state of affairs (e.g., where Linda thinks her cat is hiding). By M = 4;0–4;6, children pass Diverse Desires and Diverse Beliefs but still fail Knowledge Access, False Belief, and Real/Apparent Emotion. |
| Knowledge access | ~4–4.5 years | Wellman & Liu (2004) | Tests "that perceptual access leads to knowledge", so whether a character who "has never ever seen inside this box" can be said to know its contents. *(NB: §1 tags this dimension 3–4 yr via Wimmer/Hogrefe/Perner 1988 & Pratt & Bryant 1990 — reconcile.)* |
| Order-1 false belief | Below-chance until ~3;5, above-chance and reliably passing by ~4 years | Wimmer & Perner (1983); Wellman et al. (meta-analysis, 2001) | Wimmer & Perner: "None of the 3-4-year-old, 57% of 4-6-year-old, and 86% of 6-9-year-old children pointed correctly...to location x in both sketches" (p. 103). Wellman et al.: "At younger ages—essentially 41 months (3 years, 5 months) and younger—children performed below chance...At older ages—essentially 48 months (4 years) and older—they performed above chance, significantly correct" (p. 663). |
| Order-2 false belief | Emerging ~6–7 years under supportive/prompted conditions; robust by ~8–9 years unaided | Perner & Wimmer (1985) | "Results suggested unexpected early competence around the age of 6 and 7 years, shown under optimal conditions when inference of second-order beliefs was prompted" (p. 437). "Roughly speaking many 6-year-olds and almost all 7- to 9-year-olds are able to mentally represent and understand second-order beliefs" (p. 468). Unaided condition: only 12% correct at age 6, rising to 75% by age 10. |
| Order-3+ | Fragile at ~10–11 years (near/slightly-above chance); still developing through adolescence into early adulthood | Liddle & Nettle (2006); Valle et al. (2015) | Liddle & Nettle: "Ten and eleven year old children master first and second level theory of mind problems, are slightly above chance on third level problems, and perform at chance on fourth level" (p. 231). Valle et al.: "young adults (M = .810) perform significantly better than young adolescents (M = .557) and adolescents (M = .443)" on third-order false belief (p. 118). |

**Wellman & Liu ToM scale ordering:** diverse desires → diverse beliefs → knowledge access → contents
false belief → hidden emotion.

## 4. Precursor milestones (infancy) — context only, below the item-bank floor

The item bank starts at ~2–3 yr (Diverse Desires). The earlier infant-precursor milestones below are
kept for developmental context; they sit *below* the youngest dimension the benchmark tests, so they
inform the ordering narrative but are not item bands.

| Precursor | Age | Source |
|---|---|---|
| Goal & intention detection (precursor to Intention vs. Accident) | 5–6 months | Kamewari et al. (2005) |
| Emotion perception in face/voice (precursor to Emotion Recognition) | 7 months | Grossmann (2010) |
| Other-oriented empathy | 8–10 months | Roth-Hanania et al. (2011) |
| Prosocial behavior | by 16 months | Roth-Hanania et al. (2011) |
| Implicit/spontaneous false belief (looking-time) | 15 months | Onishi & Baillargeon (2005) |

## 5. BibTeX

> Covers §3–§4. **TODO:** add verified entries for the §1 item-bank citations flagged in the §1
> BibTeX-gap note before v0.1.

```bibtex
@article{kamewari2005sixandahalf,
  author  = {Kamewari, Kazuhide and Kato, Miki and Kanda, Takayuki and Ishiguro, Hiroshi and Hiraki, Kazuo},
  title   = {Six-and-a-half-month-old children positively attribute goals to human action and to humanoid-robot motion},
  journal = {Cognitive Development},
  year    = {2005},
  volume  = {20},
  number  = {2},
  pages   = {303--320}
}

@article{grossmann2010development,
  author  = {Grossmann, Tobias},
  title   = {The development of emotion perception in face and voice during infancy},
  journal = {Restorative Neurology and Neuroscience},
  year    = {2010},
  volume  = {28},
  number  = {2},
  pages   = {219--236},
  doi     = {10.3233/RNN-2010-0499}
}

@article{rothhanania2011empathy,
  author  = {Roth-Hanania, Ronit and Davidov, Maayan and Zahn-Waxler, Carolyn},
  title   = {Empathy development from 8 to 16 months: Early signs of concern for others},
  journal = {Infant Behavior and Development},
  year    = {2011},
  volume  = {34},
  number  = {3},
  pages   = {447--458},
  doi     = {10.1016/j.infbeh.2011.04.007}
}

@article{onishi2005baillargeon,
  author  = {Onishi, Kristine H. and Baillargeon, Renee},
  title   = {Do 15-month-old infants understand false beliefs?},
  journal = {Science},
  year    = {2005},
  volume  = {308},
  number  = {5719},
  pages   = {255--258},
  doi     = {10.1126/science.1107621}
}

@article{talwar2002development,
  author  = {Talwar, Victoria and Lee, Kang},
  title   = {Development of lying to conceal a transgression: Children's control of expressive behaviour during verbal deception},
  journal = {International Journal of Behavioral Development},
  year    = {2002},
  volume  = {26},
  number  = {5},
  pages   = {436--444},
  doi     = {10.1080/01650250143000373}
}

@article{banasikjemielniak2019childrens,
  author  = {Banasik-Jemielniak, Natalia and Bokus, Barbara},
  title   = {Children's comprehension of irony: Studies on Polish-speaking preschoolers},
  journal = {Journal of Psycholinguistic Research},
  year    = {2019},
  volume  = {48},
  number  = {5},
  pages   = {1217--1240},
  doi     = {10.1007/s10936-019-09654-x}
}

@article{glenwright2010development,
  author  = {Glenwright, Melanie and Pexman, Penny M.},
  title   = {Development of children's ability to distinguish sarcasm and verbal irony},
  journal = {Journal of Child Language},
  year    = {2010},
  volume  = {37},
  number  = {2},
  pages   = {429--451}
}

@article{perner1985john,
  author  = {Perner, Josef and Wimmer, Heinz},
  title   = {"{J}ohn thinks that {M}ary thinks that...": Attribution of second-order beliefs by 5- to 10-year-old children},
  journal = {Journal of Experimental Child Psychology},
  year    = {1985},
  volume  = {39},
  number  = {3},
  pages   = {437--471},
  doi     = {10.1016/0022-0965(85)90051-7}
}

@article{polak1999deception,
  author  = {Polak, Alan and Harris, Paul L.},
  title   = {Deception by young children following non-compliance},
  journal = {Developmental Psychology},
  year    = {1999},
  volume  = {35},
  pages   = {561--568}
}

@article{talwar2007lying,
  author  = {Talwar, Victoria and Gordon, Heidi M. and Lee, Kang},
  title   = {Lying in the elementary school years: Verbal deception and its relation to second-order belief understanding},
  journal = {Developmental Psychology},
  year    = {2007},
  volume  = {43},
  number  = {3},
  pages   = {804--810},
  doi     = {10.1037/0012-1649.43.3.804}
}

@article{osterhaus2021development,
  author  = {Osterhaus, Christopher and Koerber, Susanne},
  title   = {The development of advanced theory of mind in middle childhood: A longitudinal study from age 5 to 10 years},
  journal = {Child Development},
  year    = {2021},
  volume  = {92},
  number  = {5},
  pages   = {1872--1888},
  doi     = {10.1111/cdev.13627}
}

@article{wimmer1983beliefs,
  author  = {Wimmer, Heinz and Perner, Josef},
  title   = {Beliefs about beliefs: Representation and constraining function of wrong beliefs in young children's understanding of deception},
  journal = {Cognition},
  year    = {1983},
  volume  = {13},
  number  = {1},
  pages   = {103--128},
  doi     = {10.1016/0010-0277(83)90004-5}
}

@article{wellman2001metaanalysis,
  author  = {Wellman, Henry M. and Cross, David and Watson, Julanne},
  title   = {Meta-analysis of theory-of-mind development: The truth about false belief},
  journal = {Child Development},
  year    = {2001},
  volume  = {72},
  number  = {3},
  pages   = {655--684},
  doi     = {10.1111/1467-8624.00304}
}

@article{wellman2004scaling,
  author  = {Wellman, Henry M. and Liu, David},
  title   = {Scaling of theory-of-mind tasks},
  journal = {Child Development},
  year    = {2004},
  volume  = {75},
  number  = {2},
  pages   = {523--541},
  doi     = {10.1111/j.1467-8624.2004.00691.x}
}

@article{liddle2006higherorder,
  author  = {Liddle, Bethany and Nettle, Daniel},
  title   = {Higher-order theory of mind and social competence in school-age children},
  journal = {Journal of Cultural and Evolutionary Psychology},
  year    = {2006},
  volume  = {4},
  number  = {3--4},
  pages   = {231--246},
  doi     = {10.1556/JCEP.4.2006.3-4.3}
}

@article{valle2015theory,
  author  = {Valle, Annalisa and Massaro, Davide and Castelli, Ilaria and Marchetti, Antonella},
  title   = {Theory of mind development in adolescence and early adulthood: The growing complexity of recursive thinking ability},
  journal = {Europe's Journal of Psychology},
  year    = {2015},
  volume  = {11},
  number  = {1},
  pages   = {112--124},
  doi     = {10.5964/ejop.v11i1.829}
}

@article{schidelko2021why,
  author  = {Schidelko, Lydia P. and Huemer, Michael and Schr{\"o}der, Lara M. and Lueb, Anna S. and Perner, Josef and Rakoczy, Hannes},
  title   = {Why do children who solve false belief tasks begin to find true belief control tasks difficult? A test of pragmatic performance factors in theory of mind tasks},
  journal = {Frontiers in Psychology},
  year    = {2021},
  volume  = {12},
  pages   = {797246},
  doi     = {10.3389/fpsyg.2021.797246}
}

% ---------------------------------------------------------------------------
% Item-bank citations (§1 canonical table). Bibliographic details verified via
% web search against primary-source records (publisher / PubMed / ERIC) on
% 2026-07-14. DOIs included only where the source record listed one. Confirm
% each against the primary source, and confirm the ambiguous Ekman entry (the
% item metadata says only "(Ekman)"), before v0.1.
% ---------------------------------------------------------------------------

@article{wimmer1988informational,
  author  = {Wimmer, Heinz and Hogrefe, G.-J. and Perner, Josef},
  title   = {Children's understanding of informational access as source of knowledge},
  journal = {Child Development},
  year    = {1988},
  volume  = {59},
  number  = {2},
  pages   = {386--396}
}

@article{pratt1990looking,
  author  = {Pratt, Chris and Bryant, Peter},
  title   = {Young children understand that looking leads to knowing (so long as they are looking into a single barrel)},
  journal = {Child Development},
  year    = {1990},
  volume  = {61},
  number  = {4},
  pages   = {973--982},
  doi     = {10.1111/j.1467-8624.1990.tb02835.x}
}

% NB: item metadata cites only "(Ekman)" for basic emotion recognition; this is
% the most likely intended reference, but Ekman & Friesen (1971) is an
% alternative if the intent was cross-cultural facial-expression recognition.
@article{ekman1992argument,
  author  = {Ekman, Paul},
  title   = {An argument for basic emotions},
  journal = {Cognition and Emotion},
  year    = {1992},
  volume  = {6},
  number  = {3--4},
  pages   = {169--200},
  doi     = {10.1080/02699939208411068}
}

@article{widen2008gradually,
  author  = {Widen, Sherri C. and Russell, James A.},
  title   = {Children acquire emotion categories gradually},
  journal = {Cognitive Development},
  year    = {2008},
  volume  = {23},
  number  = {2},
  pages   = {291--312}
}

@article{perner1987threeyearolds,
  author  = {Perner, Josef and Leekam, Susan R. and Wimmer, Heinz},
  title   = {Three-year-olds' difficulty with false belief: The case for a conceptual deficit},
  journal = {British Journal of Developmental Psychology},
  year    = {1987},
  volume  = {5},
  number  = {2},
  pages   = {125--137},
  doi     = {10.1111/j.2044-835X.1987.tb01048.x}
}

@book{piaget1932moral,
  author    = {Piaget, Jean},
  title     = {The Moral Judgment of the Child},
  year      = {1932},
  publisher = {Kegan Paul, Trench, Trubner \& Co.},
  address   = {London}
}

@article{nunnerwinkler1988moral,
  author  = {Nunner-Winkler, Gertrud and Sodian, Beate},
  title   = {Children's understanding of moral emotions},
  journal = {Child Development},
  year    = {1988},
  volume  = {59},
  number  = {5},
  pages   = {1323--1338}
}

@article{harris1986realapparent,
  author  = {Harris, Paul L. and Donnelly, Kevin and Guz, Gulie R. and Pitt-Watson, Rosemary},
  title   = {Children's understanding of the distinction between real and apparent emotion},
  journal = {Child Development},
  year    = {1986},
  volume  = {57},
  number  = {4},
  pages   = {895--909}
}

@article{gross1991review,
  author  = {Gross, Alan L. and Ballif, Bonnie},
  title   = {Children's understanding of emotion from facial expressions and situations: A review},
  journal = {Developmental Review},
  year    = {1991},
  volume  = {11},
  number  = {4},
  pages   = {368--398},
  doi     = {10.1016/0273-2297(91)90019-K}
}

@article{talwar2007whitelie,
  author  = {Talwar, Victoria and Murphy, Susan M. and Lee, Kang},
  title   = {White lie-telling in children for politeness purposes},
  journal = {International Journal of Behavioral Development},
  year    = {2007},
  volume  = {31},
  number  = {1},
  pages   = {1--11},
  doi     = {10.1177/0165025406073530}
}

@article{winner1991irony,
  author  = {Winner, Ellen and Leekam, Sue},
  title   = {Distinguishing irony from deception: Understanding the speaker's second-order intention},
  journal = {British Journal of Developmental Psychology},
  year    = {1991},
  volume  = {9},
  number  = {2},
  pages   = {257--270},
  doi     = {10.1111/j.2044-835X.1991.tb00875.x}
}

@article{filippova2008irony,
  author  = {Filippova, Eva and Astington, Janet Wilde},
  title   = {Further development in social reasoning revealed in discourse irony understanding},
  journal = {Child Development},
  year    = {2008},
  volume  = {79},
  number  = {1},
  pages   = {126--138},
  doi     = {10.1111/j.1467-8624.2007.01115.x}
}

@article{hancock2000irony,
  author  = {Hancock, Jeffrey T. and Dunham, Philip J. and Purdy, Kelly},
  title   = {Children's comprehension of critical and complimentary forms of verbal irony},
  journal = {Journal of Cognition and Development},
  year    = {2000},
  volume  = {1},
  number  = {2},
  pages   = {227--248},
  doi     = {10.1207/S15327647JCD010204}
}

@article{colston2000irony,
  author  = {Colston, Herbert L.},
  title   = {On necessary conditions for verbal irony comprehension},
  journal = {Pragmatics \& Cognition},
  year    = {2000},
  volume  = {8},
  number  = {2},
  pages   = {277--324},
  doi     = {10.1075/pc.8.2.02col}
}

@article{baroncohen1999fauxpas,
  author  = {Baron-Cohen, Simon and O'Riordan, Michelle and Stone, Valerie and Jones, Rosie and Plaisted, Kate},
  title   = {Recognition of faux pas by normally developing children and children with Asperger syndrome or high-functioning autism},
  journal = {Journal of Autism and Developmental Disorders},
  year    = {1999},
  volume  = {29},
  number  = {5},
  pages   = {407--418},
  doi     = {10.1023/A:1023035012436}
}
```
