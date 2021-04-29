library("dplyr")
library("magrittr")
library("mlr")
library("xgboost")
library("caret")
library("ggplot2")

# Pré-processamento - Data Cleaning e análise de inconsistências ---- 
## Leitura do banco
treino_total <- read.csv("treino.csv") %>% tibble()
teste_total <-  read.csv("teste.csv") %>% tibble()

# Criando partiõe
set.seed(3526)
trainIndex <- createDataPartition(treino_total$inadimplente, p = .8, 
                                  list = FALSE, 
                                  times = 1)
treino <- treino_total[trainIndex, ]
teste <- treino_total[-trainIndex, ]

## Análise do tipo das variáveis dos bancos -----
str(treino)
str(teste)

## Analisando dados faltantes ----
tibble("Treino" = table(is.na(treino)), "Teste" = table(is.na(teste)))

isMissing <- function(x) { # Retorna porcentagem de missing da variável
  sum(is.na(x)) / length(x) * 100
} 
sapply(treino, isMissing)
sapply(teste, isMissing)
options(na.action='na.pass') 

## Analisando se valores são todos não-negativos ----
isNonNegative <- function(x) { # Retorna porcentagem de valores maiores ou iguais a zero
  sum(x >= 0, na.rm = TRUE) / length(x[!is.na(x)]) * 100
}
sapply(treino, isNonNegative)
sapply(teste, isNonNegative)

## Analisando proporção de classes ----
table(treino$inadimplente) / length(treino$inadimplente) * 100

# Construindo modelo
## Matriz do modelo
trn_labels <- as.numeric(treino$inadimplente)
tst_labels <- as.numeric(teste$inadimplente)
new_trn <- model.matrix(~.+0, data = treino %>% select(-"inadimplente")) 
new_tst <- model.matrix(~.+0, data = teste %>% select(-"inadimplente"))

dtreino <- xgb.DMatrix(data = new_trn, label = trn_labels) 
dteste <- xgb.DMatrix(data = new_tst, label = tst_labels)

## Parâmetros
sumwpos <- sum(trn_labels == 0)
sumwneg <- sum(trn_labels == 1)
params <-
  list(
    booster = "gbtree",
    objective = "binary:logistic",
    eta = 0.3,
    gamma = 0,
    max_depth = 6,
    min_child_weight = 1,
    subsample = 1,
    colsample_bytree = 1,
    scale_pos_weight = sumwpos / sumwneg
    )

## Testando modelos
set.seed(234)
xgbcv <-
  xgb.cv(
    params = params,
    data = dtreino,
    nrounds = 30,
    nfold = 5,
    showsd = T,
    stratified = T,
    eval_metric = "auc",
    print_every_n = 10,
    early_stop_round = 20,
    maximize = F
    )

max(xgbcv$evaluation_log$test_auc_mean)
.nrounds <- which.max(xgbcv$evaluation_log$test_auc_mean);.nrounds

## Treinando modelo escolhido
set.seed(234)
xgb1 <-
  xgb.train(
    params = params,
    data = dtreino,
    nrounds = 16,
    watchlist = list(val = dteste, train = dtreino),
    print_every_n = 10,
    early_stop_round = 10,
    maximize = F ,
    eval_metric = "auc"
  )
 
# Performance do modelo
xgbpred <- predict(xgb1, dteste)
xgbpred <- ifelse (xgbpred > 0.5,1,0)
confusionMatrix(as.factor(xgbpred), as.factor(tst_labels))

# Importância das variáveis
mat <- xgb.importance (feature_names = colnames(new_trn),model = xgb1)
xgb.ggplot.importance(importance_matrix = mat[1:10]) +
  ylab("Variáveis") + xlab("Importância") + ggtitle("Importância das variáveis")

# Predição para conjunto de teste fornecido
## Matriz do modelo
new_tst_total <- model.matrix(~.+0, data = teste_total)
dteste_total <- xgb.DMatrix(data = new_tst_total)

xgbpred_tst <- predict(xgb1, dteste_total)
xgbpred_tst <- ifelse (xgbpred_tst > 0.5,1,0)

# Criando predições para o conjunto de teste fornecido
write.csv(teste_total %>% mutate(inadimplente = xgbpred_tst), "teste.csv")
View(read.csv("teste2.csv"))
