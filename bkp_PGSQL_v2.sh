#!/bin/bash
#============================================================================================
#       ARQUIVO:  bkp_PGSQLv2.sh
#       DESCRICAO: Verifica ponto de montagem de storage, remove backups com mais de X dias, gera um dump do banco e compacta. Em caso de erro notifica via email.
#       REQUISITOS: 
#       * HOMOLOGADO:  Em distribuições CentOS 6.x 
#       - OBRIGATÓRIO o arquivo de variáveis "PARAMETROSBKPBD" disponibilizado no PATH (/usr/bin/PARAMETROSBKPBD).
#       - OBRIGATÓRIO em caso de discos rígidos/virtualizados serem registrados em /etc/fstab.
#       - OBRIGATÓRIO caminho de montagem em /mnt para discos e unidades de rede.
#       - Todos os ajustes de cada cliente deverão ser escritos no arquivo de variáveis PARAMETROSBKPBD.
#       VERSAO:  0.3.2
#       CRIADO:  12/02/2020
#	AUTOR: Matheus Martins
#       REVISAO:  ---
#       CHANGELOG:
#       13/02/2020 15:00 
#       - Adicionada função de envio de emails
#       14/02/2020 17:00
#       - Ajuste na trap com as saidas específicas de saída
#       17/02/2020 11:15
#       - Recriado cabeçalho de script priorizando a ordem de checagem de discos e quantidade
#       18/02/2020 10:00
#       - Ajustado leitura do fstab para não coletar linhas com /mnt/storage que comecem com comentários
#	21/02/2020 10:30
#	- Adicionada validação para casos de backup em pasta de rede
#	- Adicionado no repositório para versionamento git/github
#       16/03/2020 11:20
#       - Ajustado cabeçalho e corpo de email para melhor informar das notificações de eventos de erros ocorridos
#       22/03/2020 12:00
#       - Adicionado webook de notificação do github no Discord
#       24/03/2020 09:00
#       - Ajuste nas funções de sendmail e trap error que não estavam exportando o arquivos de PARAMETROSBKPBD
#       - Ajuste na retenção do backup, removendo assim backups antigos mesmo se o servidor estiver desligado em sua proxima execução
#       19/08/2020 00:00
#       - Adicionado lockfile para evitar execucao simultanea
#		05/10/2021 22:00
#		- Ajustada identação e removido lockfile
#=============================================================================================

source PARAMETROS

send_mail()
{	source PARAMETROS
	echo -e "Verificar com urgencia o status de backup do banco de dados de $(hostname) ocorrido em $DATALOG em $DESTINOBASE" | mail -s "$hostname - ERRO NO PROCESSO DE BACKUP... LOG LOCALIZADO EM $LOGBANCO" ${TO[$x]}
	echo -e "$DATALOG $LOGBANCO: Email de notificação enviado para $TO" >> $LOGBANCO
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
if [ $QTDISCO -eq 0 ]; then
	echo "OK Nao existem particoes a serem montadas"
	echo "Destino de backup em /dados/backup/PGSQL"
	DESTINO="/$DESTINOBASE/$DATAHORA"
	elif [ ! -d $DESTINOBASE ]; then
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
if [ "$ESPACODISCO" -lt 85 -a -d $DESTINOBASE ] ;then
	#Removendo backup antigo
	find $DESTINOBASE/ -maxdepth 1 -mtime +$MAXRET -exec rm -rfv "{}" \; >> $LOGBANCO && echo "$DATALOG: Removidos os backups antigos:" >> $LOGBANCO

	#Cria pasta no destino com data/hora
	/bin/mkdir -p "$DESTINO"

	#Gerando backup de banco
	echo "$DATALOG: Gerando Backup Base - dbcallcenter em: $DESTINO" >> $LOGBANCO
	/usr/bin/pg_dump -U dbcallcenter $BASE | gzip -9 > $DESTINO/bkp_base_$BASE.sql.gz
	echo "$DATALOG: Backup criado: $DESTINO/bkp_base_$BASE.sql.gz" >> $LOGBANCO

	#Vaccum analyze
	/usr/bin/psql -U dbcallcenter -c "vacuum analyze"; >> $LOGBANCO

else
	echo "$DATALOG: $PONTOMONTAGEM com menos de 15% de espaço livre." >> $LOGBANCO;
	send_mail
fi
