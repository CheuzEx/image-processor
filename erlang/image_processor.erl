-module(image_processor).
-export([main/1]).

-define(RACKET_SCRIPT, "scheme/filtro.rkt").
-define(TIMEOUT_MS, 30000).
-define(MAX_REINTENTOS, 1).

main([Input, Output, NStr]) -> main([Input, Output, NStr, "gaussian"]);
main([Input, Output, NStr, Filtro0]) ->
    {Ancho, Alto, Max, Filas} = ppm:leerPPM(Input),
    Filtro = string:to_upper(Filtro0),
    N = forzarN(Filtro, validarN(NStr, Alto)),
    Bandas = dividirBandas(N, Alto),
    Total = length(Bandas),
    Cupo = min(Total, max(1, erlang:system_info(schedulers_online) * 4)),
    Ctx = {Filas, Ancho, Alto, radio(Filtro), Filtro, params(Filtro), Bandas},
    io:format("Procesando ~s (~px~p) filtro=~s regiones=~p cupo=~p~n",
              [Input, Ancho, Alto, Filtro, Total, Cupo]),
    T0 = erlang:monotonic_time(millisecond),
    %% OJO: self() se captura AQUI, en el proceso de main -- si se
    %% evaluara dentro del fun del spawn, apuntaria al propio Server
    %% (se ejecuta ya en el proceso nuevo) y el aviso de {terminado,_}
    %% nunca llegaria a main (deadlock).
    Interesado = self(),
    Server = spawn(fun() -> imgServer({#{}, Total, #{}, lists:seq(Cupo + 1, Total)}, Ctx, Interesado) end),
    lanzarTodos(Server, lists:seq(1, Cupo), Ctx),
    recibir(Total, T0, Output, Max, Ancho).

recibir(Total, T0, Output, Max, Ancho) ->
    receive
        {terminado, Resultados} ->
            case hayError(Resultados) of
                true ->
                    io:format("ERROR: alguna region fallo, no se escribe salida~n"),
                    halt(1);
                false ->
                    FilasFinal = reconstruir(Resultados),
                    AltoF = tuple_size(FilasFinal),
                    AnchoF = caso(AltoF > 0, tuple_size(element(1, FilasFinal)), Ancho),
                    ppm:escribirPPM(Output, AnchoF, AltoF, Max, FilasFinal),
                    T1 = erlang:monotonic_time(millisecond),
                    io:format("Listo ~s (~px~p) Tp=~p ms~n", [Output, AnchoF, AltoF, T1 - T0])
            end
    after ?TIMEOUT_MS * (Total + 1) ->
            io:format("ERROR: timeout esperando al servidor~n"),
            halt(1)
    end.

caso(true, A, _) -> A;
caso(false, _, B) -> B.

forzarN("TRANSPONER", N) when N > 1 ->
    io:format("Aviso: transponer es global, se fuerza N=1~n"),
    1;
forzarN(_, N) -> N.

validarN(NStr, Alto) ->
    case string:to_integer(NStr) of
        {N, []} when N > 0, N =< Alto -> N;
        {N, []} when N > Alto ->
            io:format("Aviso: N=~p > filas=~p, se usa ~p~n", [N, Alto, Alto]),
            Alto;
        _ ->
            io:format("ERROR: N debe ser entero positivo~n"),
            halt(1)
    end.

dividirBandas(N, Alto) ->
    dividir(0, N, Alto div N, Alto rem N, []).

dividir(_, 0, _, _, Acc) -> lists:reverse(Acc);
dividir(Inicio, N, Base, Resto, Acc) ->
    Fin = Inicio + Base + caso(Resto > 0, 1, 0),
    dividir(Fin, N - 1, Base, max(Resto - 1, 0), [{Inicio, Fin} | Acc]).

radio("GAUSSIAN") -> 1;
radio("SHARPEN") -> 1;
radio(_) -> 0.

params("GAUSSIAN") -> "3 16 1 2 1 2 4 2 1 2 1";
params("SHARPEN") -> "0";
params("THRESHOLD") -> "128";
params("BRIGHTNESS") -> "30";
params(_) -> "0".

%% Estado del servidor: {Resultados, Pendientes, Reintentos, Cola}
%% (tupla simple, al estilo de {D,T} en pi.erl). El contexto (Ctx) es
%% de solo lectura, se pasa aparte -- no forma parte del estado que muta.
imgServer(Estado, Ctx, Interesado) ->
    receive
        {resultado, Idx, R} ->
            {Estado2, Aviso} = registrar(Estado, Idx, R, Ctx),
            notificar(Aviso, Interesado),
            imgServer(Estado2, Ctx, Interesado);
        fin -> ok
    end.

notificar({si, Resultados}, Interesado) -> Interesado ! {terminado, Resultados};
notificar(no, _) -> ok.

registrar({Resultados, _, _, _} = Estado, Idx, _, _) when is_map_key(Idx, Resultados) ->
    {Estado, no};
registrar({Resultados, Pendientes, Reintentos, Cola}, Idx, {error, Motivo}, Ctx) ->
    Intentos = maps:get(Idx, Reintentos, 0),
    case Intentos < ?MAX_REINTENTOS of
        true ->
            lanzar(self(), Idx, Ctx),
            {{Resultados, Pendientes, maps:put(Idx, Intentos + 1, Reintentos), Cola}, no};
        false ->
            marcarCompleto(Resultados, Pendientes, Reintentos, Cola, Idx, {error, Motivo}, Ctx)
    end;
registrar({Resultados, Pendientes, Reintentos, Cola}, Idx, R, Ctx) ->
    marcarCompleto(Resultados, Pendientes, Reintentos, Cola, Idx, R, Ctx).

marcarCompleto(Resultados, Pendientes, Reintentos, Cola, Idx, R, Ctx) ->
    Resultados2 = maps:put(Idx, R, Resultados),
    Pendientes2 = Pendientes - 1,
    Cola2 = case Cola of
                [] -> [];
                [Sig | Resto] -> lanzar(self(), Sig, Ctx), Resto
            end,
    Estado2 = {Resultados2, Pendientes2, Reintentos, Cola2},
    case Pendientes2 of
        0 -> {Estado2, {si, ordenar(Resultados2, Ctx)}};
        _ -> {Estado2, no}
    end.

ordenar(Resultados, {_, _, _, _, _, _, Bandas}) ->
    [maps:get(I, Resultados) || I <- lists:seq(1, length(Bandas))].

hayError(Resultados) -> lists:any(fun({error, _}) -> true; (_) -> false end, Resultados).

lanzarTodos(_, [], _) -> ok;
lanzarTodos(Server, [Idx | Resto], Ctx) ->
    lanzar(Server, Idx, Ctx),
    lanzarTodos(Server, Resto, Ctx).

lanzar(Server, Idx, Ctx) ->
    {Filas, Ancho, Alto, Radio, Filtro, Params, Bandas} = Ctx,
    {Inicio, Fin} = lists:nth(Idx, Bandas),
    Peticion = construirPeticion(Filas, Ancho, Alto, Inicio, Fin, Radio, Filtro, Params),
    spawn(fun() -> trabajar(Server, Idx, Peticion) end).

trabajar(Server, Idx, Peticion) ->
    Port = open_port({spawn, "racket " ++ ?RACKET_SCRIPT}, [binary, exit_status, {packet, 4}]),
    port_command(Port, list_to_binary(Peticion)),
    Server ! {resultado, Idx, esperar(Port)}.

esperar(Port) ->
    receive
        {Port, {data, Bin}} ->
            catch port_close(Port),
            parseRespuesta(binary_to_list(Bin));
        {Port, {exit_status, S}} when S =/= 0 ->
            {error, {schemeExit, S}}
    after ?TIMEOUT_MS ->
            catch port_close(Port),
            {error, timeout}
    end.

parseRespuesta(Texto) ->
    case string:tokens(Texto, "\n") of
        ["OK", Dims, Pixels | _] ->
            [_, AnchoS, AltoS] = string:tokens(Dims, " "),
            ["PIXELS" | NumsS] = string:tokens(Pixels, " "),
            {ok, list_to_integer(AnchoS), list_to_integer(AltoS),
             tripletas([list_to_integer(S) || S <- NumsS])};
        [Primera | _] ->
            case string:tokens(Primera, " ") of
                ["ERROR" | Resto] -> {error, {schemeError, string:join(Resto, " ")}};
                _ -> {error, {respuestaInvalida, Texto}}
            end;
        _ -> {error, {respuestaInvalida, Texto}}
    end.

tripletas([]) -> [];
tripletas([R, G, B | T]) -> [{R, G, B} | tripletas(T)].

construirPeticion(Filas, Ancho, Alto, Inicio, Fin, Radio, Filtro, Params) ->
    Ini = Inicio - Radio,
    Fn = Fin + Radio - 1,
    Pix = [ppm:obtenerPixelClamp(Filas, Ancho, Alto, {F, C})
           || F <- lists:seq(Ini, Fn), C <- lists:seq(0, Ancho - 1)],
    PixStr = string:join([io_lib:format("~p ~p ~p", [R, G, B]) || {R, G, B} <- Pix], " "),
    io_lib:format("FILTER ~s~nPARAMS ~s~nDIMS ~p ~p~nHALO 0 ~p 0 ~p~nPIXELS ~s~n",
                  [Filtro, Params, Ancho, Fn - Ini + 1, Radio, Radio, PixStr]).

reconstruir(Resultados) ->
    FilasPorBanda = [agrupar(Pixeles, Ancho2) || {ok, Ancho2, _, Pixeles} <- Resultados],
    list_to_tuple([list_to_tuple(F) || F <- lists:append(FilasPorBanda)]).

agrupar([], _) -> [];
agrupar(L, Ancho) ->
    {Fila, Resto} = lists:split(Ancho, L),
    [Fila | agrupar(Resto, Ancho)].
