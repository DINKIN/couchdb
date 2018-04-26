% Licensed under the Apache License, Version 2.0 (the "License"); you may not
% use this file except in compliance with the License. You may obtain a copy of
% the License at
%
%   http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
% License for the specific language governing permissions and limitations under
% the License.

-module(test_engine_fold_purge_infos).
-compile(export_all).


-include_lib("eunit/include/eunit.hrl").
-include_lib("couch/include/couch_db.hrl").


-define(NUM_DOCS, 100).


cet_empty_purged_docs() ->
    {ok, Db} = test_engine_util:create_db(),
    ?assertEqual({ok, []}, couch_db_engine:fold_purge_infos(
            Db, 0, fun fold_fun/2, [], [])).


cet_all_purged_docs() ->
    {ok, Db1} = test_engine_util:create_db(),

    {RActions, RIds} = lists:foldl(fun(Id, {CActions, CIds}) ->
        Id1 = docid(Id),
        Action = {create, {Id1, {[{<<"int">>, Id}]}}},
        {[Action| CActions], [Id1| CIds]}
     end, {[], []}, lists:seq(1, ?NUM_DOCS)),
    Actions = lists:reverse(RActions),
    Ids = lists:reverse(RIds),
    {ok, Db2} = test_engine_util:apply_batch(Db1, Actions),

    FDIs = couch_db_engine:open_docs(Db2, Ids),
    {RevActions2, RevIdRevs} = lists:foldl(fun(FDI, {CActions, CIdRevs}) ->
        Id = FDI#full_doc_info.id,
        PrevRev = test_engine_util:prev_rev(FDI),
        Rev = PrevRev#rev_info.rev,
        Action = {purge, {Id, Rev}},
        {[Action| CActions], [{Id, [Rev]}| CIdRevs]}
     end, {[], []}, FDIs),
    {Actions2, IdsRevs} = {lists:reverse(RevActions2), lists:reverse(RevIdRevs)},

    {ok, Db3} = test_engine_util:apply_batch(Db2, Actions2),
    {ok, PurgedIdRevs} = couch_db_engine:fold_purge_infos(
            Db3, 0, fun fold_fun/2, [], []),
    ?assertEqual(IdsRevs, lists:reverse(PurgedIdRevs)).


cet_start_seq() ->
    {ok, Db1} = test_engine_util:create_db(),
    Actions1 = [
        {create, {docid(1), {[{<<"int">>, 1}]}}},
        {create, {docid(2), {[{<<"int">>, 2}]}}},
        {create, {docid(3), {[{<<"int">>, 3}]}}},
        {create, {docid(4), {[{<<"int">>, 4}]}}},
        {create, {docid(5), {[{<<"int">>, 5}]}}}
    ],
    Ids = [docid(1), docid(2), docid(3), docid(4), docid(5)],
    {ok, Db2} = test_engine_util:apply_actions(Db1, Actions1),

    FDIs = couch_db_engine:open_docs(Db2, Ids),
    {RActions2, RIdRevs} = lists:foldl(fun(FDI, {CActions, CIdRevs}) ->
        Id = FDI#full_doc_info.id,
        PrevRev = test_engine_util:prev_rev(FDI),
        Rev = PrevRev#rev_info.rev,
        Action = {purge, {Id, Rev}},
        {[Action| CActions], [{Id, [Rev]}| CIdRevs]}
    end, {[], []}, FDIs),
    {ok, Db3} = test_engine_util:apply_actions(Db2, lists:reverse(RActions2)),

    StartSeq = 3,
    StartSeqIdRevs = lists:nthtail(StartSeq, lists:reverse(RIdRevs)),
    {ok, PurgedIdRevs} = couch_db_engine:fold_purge_infos(
            Db3, StartSeq, fun fold_fun/2, [], []),
    ?assertEqual(StartSeqIdRevs, lists:reverse(PurgedIdRevs)).


cet_id_rev_repeated() ->
    {ok, Db1} = test_engine_util:create_db(),

    Actions1 = [
        {create, {<<"foo">>, {[{<<"vsn">>, 1}]}}},
        {conflict, {<<"foo">>, {[{<<"vsn">>, 2}]}}}
    ],
    {ok, Db2} = test_engine_util:apply_actions(Db1, Actions1),

    [FDI1] = couch_db_engine:open_docs(Db2, [<<"foo">>]),
    PrevRev1 = test_engine_util:prev_rev(FDI1),
    Rev1 = PrevRev1#rev_info.rev,
    Actions2 = [
        {purge, {<<"foo">>, Rev1}}
    ],
    {ok, Db3} = test_engine_util:apply_actions(Db2, Actions2),
    PurgedIdRevs0 = [{<<"foo">>, [Rev1]}],
    {ok, PurgedIdRevs1} = couch_db_engine:fold_purge_infos(
            Db3, 0, fun fold_fun/2, [], []),
    ?assertEqual(PurgedIdRevs0, PurgedIdRevs1),
    ?assertEqual(1, couch_db_engine:get_purge_seq(Db3)),

    % purge the same Id,Rev when the doc still exists
    {ok, Db4} = test_engine_util:apply_actions(Db3, Actions2),
    {ok, PurgedIdRevs2} = couch_db_engine:fold_purge_infos(
            Db4, 0, fun fold_fun/2, [], []),
    ?assertEqual(PurgedIdRevs0, PurgedIdRevs2),
    ?assertEqual(1, couch_db_engine:get_purge_seq(Db4)),

    [FDI2] = couch_db_engine:open_docs(Db4, [<<"foo">>]),
    PrevRev2 = test_engine_util:prev_rev(FDI2),
    Rev2 = PrevRev2#rev_info.rev,
    Actions3 = [
        {purge, {<<"foo">>, Rev2}}
    ],
    {ok, Db5} = test_engine_util:apply_actions(Db4, Actions3),
    PurgedIdRevs00 = [{<<"foo">>, [Rev1]}, {<<"foo">>, [Rev2]}],

    % purge the same Id,Rev when the doc was completely purged
    {ok, Db6} = test_engine_util:apply_actions(Db5, Actions3),
    {ok, PurgedIdRevs3} = couch_db_engine:fold_purge_infos(
            Db6, 0, fun fold_fun/2, [], []),
    ?assertEqual(PurgedIdRevs00, lists:reverse(PurgedIdRevs3)),
    ?assertEqual(2, couch_db_engine:get_purge_seq(Db6)).


fold_fun({_PSeq, _UUID, Id, Revs}, Acc) ->
    {ok, [{Id, Revs} | Acc]}.


docid(I) ->
    Str = io_lib:format("~4..0b", [I]),
    iolist_to_binary(Str).
