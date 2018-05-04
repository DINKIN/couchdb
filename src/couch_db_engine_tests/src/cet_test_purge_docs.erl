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

-module(cet_test_purge_docs).
-compile(export_all).
-compile(nowarn_export_all).


-include_lib("eunit/include/eunit.hrl").
-include_lib("couch/include/couch_db.hrl").


setup_test() ->
    {ok, Db} = cet_util:create_db(),
    Db.


teardown_test(Db) ->
    ok = couch_server:delete(couch_db:name(Db), []).


cet_purge_simple(Db1) ->
    Actions1 = [
        {create, {<<"foo">>, {[{<<"vsn">>, 1}]}}}
    ],
    {ok, Db2} = cet_util:apply_actions(Db1, Actions1),
    {ok, PIdRevs2} = couch_db_engine:fold_purge_infos(
            Db2, 0, fun fold_fun/2, [], []),

    ?assertEqual(1, couch_db_engine:get_doc_count(Db2)),
    ?assertEqual(0, couch_db_engine:get_del_doc_count(Db2)),
    ?assertEqual(1, couch_db_engine:get_update_seq(Db2)),
    ?assertEqual(0, couch_db_engine:get_purge_seq(Db2)),
    ?assertEqual([], PIdRevs2),

    [FDI] = couch_db_engine:open_docs(Db2, [<<"foo">>]),
    PrevRev = cet_util:prev_rev(FDI),
    Rev = PrevRev#rev_info.rev,

    Actions2 = [
        {purge, {<<"foo">>, Rev}}
    ],
    {ok, Db3} = cet_util:apply_actions(Db2, Actions2),
    {ok, PIdRevs3} = couch_db_engine:fold_purge_infos(
            Db3, 0, fun fold_fun/2, [], []),

    ?assertEqual(0, couch_db_engine:get_doc_count(Db3)),
    ?assertEqual(0, couch_db_engine:get_del_doc_count(Db3)),
    ?assertEqual(2, couch_db_engine:get_update_seq(Db3)),
    ?assertEqual(1, couch_db_engine:get_purge_seq(Db3)),
    ?assertEqual([{<<"foo">>, [Rev]}], PIdRevs3).


cet_purge_UUID(Db1) ->
    Actions1 = [
        {create, {<<"foo">>, {[{<<"vsn">>, 1}]}}}
    ],
    {ok, Db2} = cet_util:apply_actions(Db1, Actions1),
    {ok, PIdRevs2} = couch_db_engine:fold_purge_infos(
            Db2, 0, fun fold_fun/2, [], []),

    ?assertEqual(1, couch_db_engine:get_doc_count(Db2)),
    ?assertEqual(0, couch_db_engine:get_del_doc_count(Db2)),
    ?assertEqual(1, couch_db_engine:get_update_seq(Db2)),
    ?assertEqual(0, couch_db_engine:get_purge_seq(Db2)),
    ?assertEqual([], PIdRevs2),

    [FDI] = couch_db_engine:open_docs(Db2, [<<"foo">>]),
    PrevRev = cet_util:prev_rev(FDI),
    Rev = PrevRev#rev_info.rev,

    Actions2 = [
        {purge, {<<"foo">>, Rev}}
    ],
    {ok, Db3} = cet_util:apply_actions(Db2, Actions2),
    {ok, PIdRevs3} = couch_db_engine:fold_purge_infos(
            Db3, 0, fun fold_fun/2, [], []),

    ?assertEqual(0, couch_db_engine:get_doc_count(Db3)),
    ?assertEqual(0, couch_db_engine:get_del_doc_count(Db3)),
    ?assertEqual(2, couch_db_engine:get_update_seq(Db3)),
    ?assertEqual(1, couch_db_engine:get_purge_seq(Db3)),
    ?assertEqual([{<<"foo">>, [Rev]}], PIdRevs3),

    {ok, {PSeq, UUID}} = couch_db_engine:fold_purge_infos(
            Db3, 0, fun first_uuid/2, [], []),
    ?assertEqual(1, PSeq),
    ?assert(is_binary(UUID)).


cet_purge_conflicts(Db1) ->
    Actions1 = [
        {create, {<<"foo">>, {[{<<"vsn">>, 1}]}}},
        {conflict, {<<"foo">>, {[{<<"vsn">>, 2}]}}}
    ],
    {ok, Db2} = cet_util:apply_actions(Db1, Actions1),
    {ok, PIdRevs2} = couch_db_engine:fold_purge_infos(
            Db2, 0, fun fold_fun/2, [], []),

    ?assertEqual(1, couch_db_engine:get_doc_count(Db2)),
    ?assertEqual(0, couch_db_engine:get_del_doc_count(Db2)),
    ?assertEqual(2, couch_db_engine:get_update_seq(Db2)),
    ?assertEqual(0, couch_db_engine:get_purge_seq(Db2)),
    ?assertEqual([], PIdRevs2),

    [FDI1] = couch_db_engine:open_docs(Db2, [<<"foo">>]),
    PrevRev1 = cet_util:prev_rev(FDI1),
    Rev1 = PrevRev1#rev_info.rev,

    Actions2 = [
        {purge, {<<"foo">>, Rev1}}
    ],
    {ok, Db3} = cet_util:apply_actions(Db2, Actions2),
    {ok, PIdRevs3} = couch_db_engine:fold_purge_infos(
            Db3, 0, fun fold_fun/2, [], []),

    ?assertEqual(1, couch_db_engine:get_doc_count(Db3)),
    ?assertEqual(0, couch_db_engine:get_del_doc_count(Db3)),
    ?assertEqual(3, couch_db_engine:get_update_seq(Db3)),
    ?assertEqual(1, couch_db_engine:get_purge_seq(Db3)),
    ?assertEqual([{<<"foo">>, [Rev1]}], PIdRevs3),

    [FDI2] = couch_db_engine:open_docs(Db3, [<<"foo">>]),
    PrevRev2 = cet_util:prev_rev(FDI2),
    Rev2 = PrevRev2#rev_info.rev,

    Actions3 = [
        {purge, {<<"foo">>, Rev2}}
    ],
    {ok, Db4} = cet_util:apply_actions(Db3, Actions3),
    {ok, PIdRevs4} = couch_db_engine:fold_purge_infos(
            Db4, 0, fun fold_fun/2, [], []),

    ?assertEqual(0, couch_db_engine:get_doc_count(Db4)),
    ?assertEqual(0, couch_db_engine:get_del_doc_count(Db4)),
    ?assertEqual(4, couch_db_engine:get_update_seq(Db4)),
    ?assertEqual(2, couch_db_engine:get_purge_seq(Db4)),
    ?assertEqual([{<<"foo">>, [Rev2]}, {<<"foo">>, [Rev1]}], PIdRevs4).


cet_add_delete_purge(Db1) ->
    Actions1 = [
        {create, {<<"foo">>, {[{<<"vsn">>, 1}]}}},
        {delete, {<<"foo">>, {[{<<"vsn">>, 2}]}}}
    ],

    {ok, Db2} = cet_util:apply_actions(Db1, Actions1),
    {ok, PIdRevs2} = couch_db_engine:fold_purge_infos(
            Db2, 0, fun fold_fun/2, [], []),

    ?assertEqual(0, couch_db_engine:get_doc_count(Db2)),
    ?assertEqual(1, couch_db_engine:get_del_doc_count(Db2)),
    ?assertEqual(2, couch_db_engine:get_update_seq(Db2)),
    ?assertEqual(0, couch_db_engine:get_purge_seq(Db2)),
    ?assertEqual([], PIdRevs2),

    [FDI] = couch_db_engine:open_docs(Db2, [<<"foo">>]),
    PrevRev = cet_util:prev_rev(FDI),
    Rev = PrevRev#rev_info.rev,

    Actions2 = [
        {purge, {<<"foo">>, Rev}}
    ],
    {ok, Db3} = cet_util:apply_actions(Db2, Actions2),
    {ok, PIdRevs3} = couch_db_engine:fold_purge_infos(
            Db3, 0, fun fold_fun/2, [], []),

    ?assertEqual(0, couch_db_engine:get_doc_count(Db3)),
    ?assertEqual(0, couch_db_engine:get_del_doc_count(Db3)),
    ?assertEqual(3, couch_db_engine:get_update_seq(Db3)),
    ?assertEqual(1, couch_db_engine:get_purge_seq(Db3)),
    ?assertEqual([{<<"foo">>, [Rev]}], PIdRevs3).


cet_add_two_purge_one(Db1) ->
    Actions1 = [
        {create, {<<"foo">>, {[{<<"vsn">>, 1}]}}},
        {create, {<<"bar">>, {[]}}}
    ],

    {ok, Db2} = cet_util:apply_actions(Db1, Actions1),
    {ok, PIdRevs2} = couch_db_engine:fold_purge_infos(
            Db2, 0, fun fold_fun/2, [], []),

    ?assertEqual(2, couch_db_engine:get_doc_count(Db2)),
    ?assertEqual(0, couch_db_engine:get_del_doc_count(Db2)),
    ?assertEqual(2, couch_db_engine:get_update_seq(Db2)),
    ?assertEqual(0, couch_db_engine:get_purge_seq(Db2)),
    ?assertEqual([], PIdRevs2),

    [FDI] = couch_db_engine:open_docs(Db2, [<<"foo">>]),
    PrevRev = cet_util:prev_rev(FDI),
    Rev = PrevRev#rev_info.rev,

    Actions2 = [
        {purge, {<<"foo">>, Rev}}
    ],
    {ok, Db3} = cet_util:apply_actions(Db2, Actions2),
    {ok, PIdRevs3} = couch_db_engine:fold_purge_infos(
            Db3, 0, fun fold_fun/2, [], []),

    ?assertEqual(1, couch_db_engine:get_doc_count(Db3)),
    ?assertEqual(0, couch_db_engine:get_del_doc_count(Db3)),
    ?assertEqual(3, couch_db_engine:get_update_seq(Db3)),
    ?assertEqual(1, couch_db_engine:get_purge_seq(Db3)),
    ?assertEqual([{<<"foo">>, [Rev]}], PIdRevs3).


fold_fun({_Pseq, _UUID, Id, Revs}, Acc) ->
    {ok, [{Id, Revs} | Acc]}.


first_uuid({PSeq, UUID, _, _}, _) ->
    {stop, {PSeq, UUID}}.
