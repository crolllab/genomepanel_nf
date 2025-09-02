library(tidyverse)

##############################
# Plot VCF filtering stats
##############################

### Load the VCF filtering data
df <- read.csv("final_variants.metrics.csv.gz", sep = ",", header = F)

names(df) <- c("CHROM", "POS", "QUAL", "AN", "MQ", "DP","QD")

ggplot(df, aes(x = QUAL)) +
  geom_density() +
  scale_x_log10() +
  geom_vline(xintercept = 1000, colour="red") +
  labs(x = "QUAL", y = "proportion")
ggsave("final_variants.plots.QUAL.pdf", width = 4, height = 4)

ggplot(df, aes(x = AN)) +
  geom_density() +
  labs(x = "AN", y = "proportion")
ggsave("final_variants.plots.AN.pdf", width = 4, height = 4)

ggplot(df, aes(x = MQ)) +
  geom_density() +
  geom_vline(xintercept = 30, colour="red") +
  labs(x = "MQ", y = "proportion")
ggsave("final_variants.plots.MQ.pdf", width = 4, height = 4)

ggplot(df, aes(x = DP)) +
  geom_density() +
  scale_x_log10() +
  labs(x = "DP", y = "proportion")
ggsave("final_variants.plots.DP.pdf", width = 7, height = 4)

ggplot(df, aes(x = QD)) +
  geom_density() +
  geom_vline(xintercept = 20, colour="red") +
  labs(x = "QD", y = "proportion")
ggsave("final_variants.plots.QD.pdf", width = 4, height = 4)

##############################
# Plot VCF filtering stats
##############################

df <- read.csv("final_variants.clean.PLINK.eigenvec", sep = " ", header = F)

pca.data <- as.data.frame(allchr.pc$scores)

## visualisation de la structure, ajout de texte identifiant les populations
ggplot(pca.data, aes(x = PC1, y = PC2, fill=region, color=region)) +
  geom_point(size = 3, alpha = 0.5) +
  geom_text(aes(x = PC1, y = PC2, label = pop), size = 2)

ggsave("PCA_structure_poptext.pdf", width = 12, height = 10)
