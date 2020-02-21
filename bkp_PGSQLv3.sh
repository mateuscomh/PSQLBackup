#!/bin/bash
#============================================================================================
#       ARQUIVO:  bkp_PGSQL.sh
#       DESCRICAO: Verifica ponto de montagem de storage, remove backups com mais de X dias, gera um dump do banco e compacta. Em caso de erro notifica via email.
#       REQUISITOS: 
#       - OBRIGATÓRIO o arquivo de variáveis "PARAMETOSBKPBD" disponibilizado no PATH (/usr/bin/PARAMETOSBKPBD).
#       - OBRIGATÓRIO em caso de discos rígidos/virtualizados serem registrados em /etc/fstab.
#       - OBRIGATÓRIO caminho de montagem em /mnt para discos e unidades de rede.
#       - Todos os ajustes de cada cliente deverão ser escritos no arquivo de variáveis PARAMETOSBKPBD.
#       VERSAO:  0.2
#       CRIADO:  12/02/2020
#	AUTOR: Matheus Martins
#       REVISAO:  ---
#       CHANGELOG:
#       13/02/2020 15:00 
#       - Adicionada função de envio de emails para infra@smartnx.io
#       14/02/2020 17:00
#       - Ajuste na trap com as saidas específicas de saída
#       17/02/2020 11:15
#       - Recriado cabeçalho de script priorizando a ordem de checagem de discos e quantidade
#       18/02/2020 10:00
#       - Ajustado leitura do fstab para não coletar linhas com /mnt/storage que comecem com comentários
#	21/02/2020 10:30
#	- Adicionada validação para casos de backup em pasta de rede
#	- Adicionado no repositório do github
#=============================================================================================

source PARAMETOSBKPBD

send_mail()
{
        echo -e "Verificar status de Backup de $(hostname)" | mail -s "$(hostname) - $DISCOMONTAGEM ERRO NO PROCESSO DE BACKUP. LOG LOCALIZADO EM $LOGBANCO" ${TO[$x]}
        echo -e "$LOGBANCO: Email de notificação enviado para $TO" >> $LOGBANCO
        exit 0
}

trap_error()
{
        echo -e "$DATALOG: Erro na execucao do script de backup de banco BACKUP DE $DATAHORA NAO REALIZADO" >> $LOGBANCO
        /bin/rm -rvf $DESTINO >> $LOGBANCO
        send_mail
        exit 0
}
trap 'trap_error' 1 2 3 5 6 15 25
#Validar se existem discos a serem montados
if [ $QTDISCO -eq 0 ];
then
        echo "OK Nao existem particoes a serem montadas"
        echo "Destino de backup em /dados/backup/PGSQL"
        DESTINOBASE="/dados/backup/PGSQL"
        DESTINO="/$DESTINOBASE/$DATAHORA"
elif [ ! -d $DESTINOBASE ];
then
        for i in $(seq $QTDISCO); do
                PONTOMONTAGEM=$(cat /etc/fstab | grep -o "/mnt/.*" | cut -d " " -f1 | head -n $i);
                sleep 2
                mount $PONTOMONTAGEM
                ESPACODISCO=$(df $DESTINOBASE | grep $DISCOMONTAGEM | sed -E "s/.* (.*)% .*$/\1/g")
        done
else
        echo -e "$DATALOG: Discos montados, iniciando processo de backup" >> $LOGBANCO
fi
sleep 2
ESPACODISCO="$( df $DESTINOBASE | sed -E "s/.* (.*)% .*$/\1/g" | tail -n 1)"
#Executando backup
if [ "$ESPACODISCO" -lt 85 -a -d $DESTINOBASE ] ;
then
#Removendo backup antigo
        /bin/rm -rfv $DESTINO/$DATAREMOVER* && echo "$DATALOG: Removido backup de: $DATAREMOVER" >> $LOGBANCO

#Cria pasta no destino com data/hora
       /bin/mkdir -p "$DESTINO"

#Gerando backup de banco
       echo "$DATALOG: Gerando Backup Base - dbcallcenter em: $DESTINO" >> $LOGBANCO
       /usr/bin/pg_dump -U dbcallcenter $BASE | gzip -9 > $DESTINO/bkp_base_$BASE.sql.gz
       /usr/bin/psql -U dbcallcenter -c "vacuum analyze"; >> $LOGBANCO
else
        echo "$DATALOG: $PONTOMONTAGEM com menos de 15% de espaço livre." >> $LOGBANCO;
        send_mail
fi
